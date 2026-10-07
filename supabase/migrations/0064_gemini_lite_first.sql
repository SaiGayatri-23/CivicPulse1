-- 0063 still tried the configured flash model first, and during congestion that costs up to 12s
-- before the lite model gets its turn (measured 16.5s end to end). For this classify-a-photo task
-- the lite model's answers are just as usable, so try it first and keep the heavier models as the
-- fallbacks.
create or replace function private.gemini_generate(p_body jsonb, p_budget_ms integer default 7000)
returns extensions.http_response
language plpgsql security definer set search_path = '' as $$
declare
  resp extensions.http_response;
  keys text[] := private.gemini_keys();
  -- Order: lite first (about 1-2s even under load), then the configured model, then heavier ones.
  models text[] := array['gemini-3.5-flash-lite', private.gemini_model(), 'gemini-3.5-flash', 'gemini-3.7-flash'];
  body jsonb;
  ki integer := 1;
  mi integer := 1;
  attempt integer := 0;
  started timestamptz := clock_timestamp();
  remaining_ms integer;
begin
  if coalesce(array_length(keys, 1), 0) = 0 then raise exception 'AI suggestions are not set up yet.'; end if;
  -- PostgREST runs RPCs as "authenticated" (30s statement_timeout, see 0059), so every attempt
  -- plus the pauses between them must fit inside p_budget_ms.
  loop
    remaining_ms := p_budget_ms - (extract(epoch from clock_timestamp() - started) * 1000)::integer;
    exit when remaining_ms < 1000 or ki > array_length(keys, 1);
    attempt := attempt + 1;
    -- Give one attempt at most 12s so a hung model cannot eat the whole budget.
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', least(remaining_ms, 12000)::text);
    body := case when models[mi] like '%lite%' then p_body #- '{generationConfig,thinkingConfig}' else p_body end;
    begin
      resp := extensions.http((
        'POST', 'https://generativelanguage.googleapis.com/v1beta/models/' || models[mi] || ':generateContent',
        array[extensions.http_header('x-goog-api-key', keys[ki])]::extensions.http_header[],
        'application/json',
        body::text
      )::extensions.http_request);
    exception when others then
      resp := null;  -- network error or curl timeout: treated like a server hiccup below
    end;
    if resp is null or resp.status in (429, 404) or (resp.status in (500, 502, 503, 504) and attempt >= 2) then
      -- Out of quota, unknown model, hung, or repeatedly failing on this key+model: move to the
      -- next model, and once every model has been tried on this key, to the next key.
      mi := mi + 1; attempt := 0;
      if mi > array_length(models, 1) then mi := 1; ki := ki + 1; end if;
    elsif resp.status in (500, 502, 503, 504) then
      perform pg_sleep(0.4 * attempt);
    else
      exit;
    end if;
  end loop;
  if resp is null then
    raise exception 'The AI service is very busy right now. Please fill this in yourself, or try again in a minute.';
  end if;
  return resp;
end;
$$;
revoke all on function private.gemini_generate(jsonb, integer) from public, anon, authenticated;
