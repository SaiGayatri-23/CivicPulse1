-- Free-tier Gemini quotas are per key per model per day, so one key only ever gives a few dozen
-- photo suggestions a day across the fallback models in 0057. Allow extra keys (each from its own
-- free Google AI Studio account) so the daily capacity scales with the number of keys, with no
-- billing. Add a key from the SQL editor with:
--   select vault.create_secret('<key>', 'gemini_api_key_2', 'Second Gemini key');
--   select vault.create_secret('<key>', 'gemini_api_key_3', 'Third Gemini key');
-- The helper walks key 1 across every model, then key 2, then key 3, stopping at the first answer.
create or replace function private.gemini_keys() returns text[]
language sql stable security definer set search_path = '' as $$
  select array_remove(array[
    (select decrypted_secret from vault.decrypted_secrets where name = 'gemini_api_key'),
    (select decrypted_secret from vault.decrypted_secrets where name = 'gemini_api_key_2'),
    (select decrypted_secret from vault.decrypted_secrets where name = 'gemini_api_key_3')
  ], null)
$$;
revoke all on function private.gemini_keys() from public, anon, authenticated;

create or replace function private.gemini_generate(p_body jsonb, p_budget_ms integer default 7000)
returns extensions.http_response
language plpgsql security definer set search_path = '' as $$
declare
  resp extensions.http_response;
  keys text[] := private.gemini_keys();
  -- Fallbacks ordered by measured speed on a photo request: 3.5-flash ~2s, 3.7-flash ~7s.
  models text[] := array[private.gemini_model(), 'gemini-3.5-flash', 'gemini-3.7-flash'];
  ki integer := 1;
  mi integer := 1;
  attempt integer := 0;
  started timestamptz := clock_timestamp();
  remaining_ms integer;
begin
  if coalesce(array_length(keys, 1), 0) = 0 then raise exception 'AI suggestions are not set up yet.'; end if;
  -- PostgREST runs RPCs as "authenticated" (20s statement_timeout, see 0056), so every attempt
  -- plus the pauses between them must fit inside p_budget_ms.
  loop
    remaining_ms := p_budget_ms - (extract(epoch from clock_timestamp() - started) * 1000)::integer;
    exit when remaining_ms < 1000 or ki > array_length(keys, 1);
    attempt := attempt + 1;
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', remaining_ms::text);
    begin
      resp := extensions.http((
        'POST', 'https://generativelanguage.googleapis.com/v1beta/models/' || models[mi] || ':generateContent',
        array[extensions.http_header('x-goog-api-key', keys[ki])]::extensions.http_header[],
        'application/json',
        p_body::text
      )::extensions.http_request);
    exception when others then
      resp := null;  -- network error or curl timeout: treated like a server hiccup below
    end;
    if resp is null or resp.status = 429 or (resp.status in (500, 502, 503, 504) and attempt >= 3) then
      -- Out of quota, rate limited, or repeatedly failing on this key+model: move to the next
      -- model, and once every model has been tried on this key, to the next key.
      mi := mi + 1; attempt := 0;
      if mi > array_length(models, 1) then mi := 1; ki := ki + 1; end if;
    elsif resp.status in (500, 502, 503, 504) then
      perform pg_sleep(0.4 * attempt);
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
