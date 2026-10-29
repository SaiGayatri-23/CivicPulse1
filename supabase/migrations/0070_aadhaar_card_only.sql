-- Sign-up now asks only for the masked Aadhaar card, not the number. When no last-4 digits are
-- supplied, the digits printed on the card (read by the AI) are used instead; the match checks
-- become: it is an Aadhaar card, it is the masked version, and the printed name matches the
-- account name. A supplied last-4 (from the profile flow) is still compared as before.
create or replace function public.citizen_auto_verify(p_image_base64 text, p_mime text, p_last4 text, p_doc_path text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  my_name text;
  user_count integer;
  resp extensions.http_response;
  raw text;
  parsed jsonb;
  is_aadhaar boolean; is_masked boolean; card_last4 text; card_name text;
  last4 text := nullif(regexp_replace(coalesce(p_last4, ''), '[^0-9]', '', 'g'), '');
  reason text;
begin
  if me is null then raise exception 'Please sign in first.'; end if;
  if public.is_guest(me) then raise exception 'Create an account to get verified.'; end if;
  if last4 is not null and last4 !~ '^[0-9]{4}$' then raise exception 'Enter the last 4 digits of your Aadhaar.'; end if;
  if p_mime not in ('image/jpeg', 'image/png', 'image/webp') then raise exception 'Unsupported image type.'; end if;
  if p_doc_path is null or p_doc_path !~ ('^' || me::text || '/') then raise exception 'Upload the card first.'; end if;
  if (select verified from public.profiles where id = me) then return jsonb_build_object('ok', true, 'verified', true, 'already', true); end if;
  if exists (select 1 from public.verification_requests where user_id = me and status = 'pending') then
    return jsonb_build_object('ok', false, 'error', 'You already have a request waiting for review.');
  end if;
  select display_name into my_name from public.profiles where id = me;

  select count(*) into user_count from public.ai_usage_log where kind = 'aadhaar_check' and user_id = me and created_at >= now() - interval '1 day';
  if user_count >= 5 then
    reason := 'Automatic check limit reached; sent for manual review.';
  else
    insert into public.ai_usage_log (user_id, kind) values (me, 'aadhaar_check');
    resp := private.gemini_generate(jsonb_build_object(
      'contents', jsonb_build_array(jsonb_build_object('parts', jsonb_build_array(
        jsonb_build_object('inlineData', jsonb_build_object('mimeType', p_mime, 'data', p_image_base64)),
        jsonb_build_object('text',
          'This should be a photo of an Indian Aadhaar card (masked version, where the first 8 digits of the 12-digit number are ' ||
          'hidden with X or asterisks and only the last 4 digits are visible). Report: is_aadhaar (true if it is an Aadhaar card), ' ||
          'is_masked (true if the first 8 digits are hidden), last4 (the last 4 visible digits of the Aadhaar number, or empty), ' ||
          'name (the person''s name printed on the card, or empty). Do not guess; use empty strings when unreadable.')
      ))),
      'generationConfig', jsonb_build_object(
        'thinkingConfig', jsonb_build_object('thinkingBudget', 0),
        'responseMimeType', 'application/json',
        'responseSchema', jsonb_build_object('type', 'OBJECT', 'properties', jsonb_build_object(
          'is_aadhaar', jsonb_build_object('type', 'BOOLEAN'),
          'is_masked', jsonb_build_object('type', 'BOOLEAN'),
          'last4', jsonb_build_object('type', 'STRING'),
          'name', jsonb_build_object('type', 'STRING')),
          'required', jsonb_build_array('is_aadhaar', 'is_masked', 'last4', 'name'))
      )
    ), 20000);
    if resp.status = 200 then
      begin
        raw := resp.content::jsonb #>> '{candidates,0,content,parts,0,text}';
        parsed := raw::jsonb;
      exception when others then parsed := null; end;
    end if;
    if parsed is null then
      reason := 'The card could not be read automatically; sent for manual review.';
    else
      is_aadhaar := coalesce((parsed ->> 'is_aadhaar')::boolean, false);
      is_masked := coalesce((parsed ->> 'is_masked')::boolean, false);
      card_last4 := right(regexp_replace(coalesce(parsed ->> 'last4', ''), '[^0-9]', '', 'g'), 4);
      card_name := coalesce(parsed ->> 'name', '');
      if not is_aadhaar then reason := 'The photo does not look like an Aadhaar card; sent for manual review.';
      elsif not is_masked then reason := 'The card is not the masked version (first 8 digits must be hidden); sent for manual review.';
      elsif card_last4 !~ '^[0-9]{4}$' then reason := 'The last 4 digits on the card could not be read; sent for manual review.';
      elsif last4 is not null and card_last4 <> last4 then reason := 'The last 4 digits on the card do not match the number entered; sent for manual review.';
      elsif not private.name_matches(card_name, my_name) then reason := 'The name on the card does not match the account name; sent for manual review.';
      end if;
      if last4 is null then last4 := card_last4; end if;
    end if;
  end if;
  if last4 is null then last4 := '0000'; end if;  -- unreadable card: placeholder so the pending request is valid; admin reads the card

  if reason is null then
    insert into public.verification_requests (user_id, doc_type, doc_path, aadhaar_last4, status, note, reviewed_at)
    values (me, 'masked_aadhaar', null, last4, 'approved', 'Verified automatically: masked Aadhaar read by AI; name matches.', now());
    update public.profiles set verified = true where id = me;
    insert into public.profile_private (id, verified_method, verified_at) values (me, 'aadhaar_ai_match', now())
    on conflict (id) do update set verified_method = 'aadhaar_ai_match', verified_at = now(), updated_at = now();
    perform public.award_points(me, 40, 'Completed verification');
    delete from storage.objects where bucket_id = 'id-docs' and name = p_doc_path;
    return jsonb_build_object('ok', true, 'verified', true);
  end if;

  insert into public.verification_requests (user_id, doc_type, doc_path, aadhaar_last4, note)
  values (me, 'masked_aadhaar', p_doc_path, last4, left(reason, 300));
  return jsonb_build_object('ok', true, 'verified', false, 'reason', reason);
end;
$$;
