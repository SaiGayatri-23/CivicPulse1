set check_function_bodies = off;
-- The photo auto-fill call to Gemini fails outright whenever Google answers 503 ("model
-- overloaded"), which the free tier does intermittently for a few seconds at a time. The key and
-- model are fine; the request simply needs to be retried. Add a shared Gemini caller that retries
-- 429/5xx responses with a short pause inside the 8s statement_timeout that PostgREST calls get,
-- and use it from suggest_report_details.
create or replace function private.gemini_generate(p_body jsonb, p_budget_ms integer default 7000)
returns extensions.http_response
language plpgsql security definer set search_path = '' as $$
declare
  resp extensions.http_response;
  attempt integer := 0;
  started timestamptz := clock_timestamp();
  remaining_ms integer;
begin
  -- PostgREST runs RPCs as "authenticated", whose statement_timeout is 8s, so the whole call
  -- (every attempt plus the pauses between them) must fit inside p_budget_ms, not just one attempt.
  loop
    attempt := attempt + 1;
    remaining_ms := p_budget_ms - (extract(epoch from clock_timestamp() - started) * 1000)::integer;
    exit when remaining_ms < 1000;
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', remaining_ms::text);
    resp := extensions.http((
      'POST', 'https://generativelanguage.googleapis.com/v1beta/models/' || private.gemini_model() || ':generateContent',
      array[extensions.http_header('x-goog-api-key', private.gemini_key())]::extensions.http_header[],
      'application/json',
      p_body::text
    )::extensions.http_request);
    -- 429 = rate limited, 500/502/503/504 = Google-side hiccup (usually answered within a second,
    -- so a short pause and a second try normally succeeds). Anything else is final.
    exit when resp.status not in (429, 500, 502, 503, 504) or attempt >= 3;
    perform pg_sleep(0.4 * attempt);
  end loop;
  if resp is null then
    raise exception 'The AI service took too long to answer. Please try again.';
  end if;
  return resp;
end;
$$;
revoke all on function private.gemini_generate(jsonb, integer) from public, anon, authenticated;

create or replace function public.suggest_report_details(p_image_base64 text, p_mime text, p_hint text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  key text;
  user_count integer;
  global_count integer;
  since timestamptz := (now() at time zone 'Asia/Kolkata')::date;
  resp extensions.http_response;
  body jsonb;
  raw text;
  parsed jsonb;
  cat text;
  categories text[] := array['roads', 'waste', 'lighting', 'water', 'parks', 'other'];
begin
  if me is null then raise exception 'Please try again in a moment.'; end if;
  if public.is_banned() then raise exception 'Your account cannot use this right now.'; end if;
  if p_mime not in ('image/jpeg', 'image/png', 'image/webp') then raise exception 'Unsupported image type.'; end if;
  if char_length(p_image_base64) > 2_000_000 then raise exception 'That image is too large for a suggestion. Try a different photo.'; end if;

  select count(*) into user_count from public.ai_usage_log where kind = 'report_autofill' and user_id = me and created_at >= since;
  if user_count >= 8 then
    raise exception 'You have used AI suggestions 8 times today. Please fill in the details yourself, or try again tomorrow.';
  end if;
  select count(*) into global_count from public.ai_usage_log where kind = 'report_autofill' and created_at >= since;
  if global_count >= 150 then
    raise exception 'AI suggestions are fully booked for today. Please fill in the details yourself.';
  end if;

  key := private.gemini_key();
  if key is null or key = '' then raise exception 'AI suggestions are not set up yet.'; end if;

  insert into public.ai_usage_log (user_id, kind) values (me, 'report_autofill');

  resp := private.gemini_generate(jsonb_build_object(
      'contents', jsonb_build_array(jsonb_build_object('parts', jsonb_build_array(
        jsonb_build_object('inlineData', jsonb_build_object('mimeType', p_mime, 'data', p_image_base64)),
        jsonb_build_object('text',
          'You help a citizen report a civic problem (potholes, garbage, streetlights, water leaks, parks, and so on) in an Indian city, ' ||
          'from a photo they took. Look at the photo and write: the single best-matching category from this exact list: ' ||
          array_to_string(categories, ', ') || '; a short, specific title (under 12 words, no location since you cannot see one); ' ||
          'and a 1-3 sentence description of what is visibly wrong, written as the reporter would write it (first person is fine). ' ||
          'Only describe what the photo actually shows. If the photo does not show a civic problem at all, set category to "other" and ' ||
          'say so plainly in the description.' ||
          coalesce(' The reporter already typed this title, use it as a hint: "' || left(p_hint, 120) || '".', '')
        )
      ))),
      'generationConfig', jsonb_build_object(
        'responseMimeType', 'application/json',
        'responseSchema', jsonb_build_object(
          'type', 'OBJECT',
          'properties', jsonb_build_object(
            'category', jsonb_build_object('type', 'STRING', 'enum', to_jsonb(categories)),
            'title', jsonb_build_object('type', 'STRING'),
            'description', jsonb_build_object('type', 'STRING'),
            'looks_like_a_problem', jsonb_build_object('type', 'BOOLEAN')
          ),
          'required', jsonb_build_array('category', 'title', 'description', 'looks_like_a_problem')
        )
      )
    ), 7000);

  if resp.status in (429, 503) then
    return jsonb_build_object('ok', false, 'error', 'The AI service is busy right now (' || resp.status || '). Please wait a few seconds and try again.');
  elsif resp.status <> 200 then
    return jsonb_build_object('ok', false, 'error', 'The AI service could not be reached right now (' || resp.status || ').');
  end if;

  begin
    body := resp.content::jsonb;
    raw := body #>> '{candidates,0,content,parts,0,text}';
    parsed := raw::jsonb;
  exception when others then
    return jsonb_build_object('ok', false, 'error', 'The AI service gave an unreadable answer.');
  end;
  if parsed is null then
    return jsonb_build_object('ok', false, 'error', 'The AI service gave an unreadable answer.');
  end if;

  cat := parsed ->> 'category';
  if cat is null or not (cat = any (categories)) then cat := 'other'; end if;

  return jsonb_build_object('ok', true, 'category', cat, 'title', left(coalesce(parsed ->> 'title', ''), 120),
    'description', left(coalesce(parsed ->> 'description', ''), 1800),
    'looks_like_a_problem', coalesce((parsed ->> 'looks_like_a_problem')::boolean, true));
end;
$$;
revoke all on function public.suggest_report_details(text, text, text) from public, anon;
grant execute on function public.suggest_report_details(text, text, text) to authenticated;
