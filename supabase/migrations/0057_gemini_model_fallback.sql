-- The Gemini free tier caps each model at a small number of requests per day (20/day for the
-- default model at the time of writing), and once that is hit every AI feature answered 429 until
-- the next day. Each model has its own separate daily quota, so when the configured model is out
-- of quota, fall through to the next one in the list instead of failing. 429 moves to the next
-- model at once; 5xx still retries the same model after a short pause, as before.
create or replace function private.gemini_generate(p_body jsonb, p_budget_ms integer default 7000)
returns extensions.http_response
language plpgsql security definer set search_path = '' as $$
declare
  resp extensions.http_response;
  -- Fallbacks ordered by measured speed on a photo request: 3.5-flash ~2s, 3.7-flash ~7s.
  models text[] := array[private.gemini_model(), 'gemini-3.5-flash', 'gemini-3.7-flash'];
  m text;
  mi integer := 1;
  attempt integer := 0;
  started timestamptz := clock_timestamp();
  remaining_ms integer;
begin
  -- PostgREST runs RPCs as "authenticated" (20s statement_timeout, see 0056), so every attempt
  -- plus the pauses between them must fit inside p_budget_ms.
  loop
    remaining_ms := p_budget_ms - (extract(epoch from clock_timestamp() - started) * 1000)::integer;
    exit when remaining_ms < 1000 or mi > array_length(models, 1);
    m := models[mi];
    attempt := attempt + 1;
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', remaining_ms::text);
    begin
      resp := extensions.http((
        'POST', 'https://generativelanguage.googleapis.com/v1beta/models/' || m || ':generateContent',
        array[extensions.http_header('x-goog-api-key', private.gemini_key())]::extensions.http_header[],
        'application/json',
        p_body::text
      )::extensions.http_request);
    exception when others then
      -- A network error or a curl timeout raises instead of returning a status. Treat it like a
      -- server hiccup: the loop below decides whether there is budget left to try again.
      resp := null;
    end;
    if resp is null then
      mi := mi + 1; attempt := 0;
    elsif resp.status = 429 then
      -- Out of quota (or rate limited) on this model: try the next one right away.
      mi := mi + 1; attempt := 0;
    elsif resp.status in (500, 502, 503, 504) and attempt < 3 then
      perform pg_sleep(0.4 * attempt);
    elsif resp.status in (500, 502, 503, 504) then
      mi := mi + 1; attempt := 0;
    else
      exit;
    end if;
  end loop;
  if resp is null then
    raise exception 'The AI service took too long to answer. Please try again.';
  end if;
  return resp;
end;
$$;
revoke all on function private.gemini_generate(jsonb, integer) from public, anon, authenticated;
