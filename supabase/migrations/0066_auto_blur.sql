-- Automatic privacy blur. Reporters rarely take the time to blur faces and number plates by
-- hand, so the client now asks the AI where they are the moment a photo is chosen and pixelates
-- those areas before upload (the unblurred image never leaves the device). Administrators get a
-- manual blur tool for anything that slipped through, which replaces the public photo in place.

-- 1. Where are the faces and number plates in this photo? Boxes are [ymin, xmin, ymax, xmax] on a
--    0-1000 scale, the convention Gemini uses for object detection.
create or replace function public.detect_privacy_regions(p_image_base64 text, p_mime text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  user_count integer;
  global_count integer;
  since timestamptz := (now() at time zone 'Asia/Kolkata')::date;
  resp extensions.http_response;
  raw text;
  parsed jsonb;
  out jsonb := '[]'::jsonb;
  r jsonb;
  b jsonb;
begin
  if me is null then raise exception 'Please try again in a moment.'; end if;
  if p_mime not in ('image/jpeg', 'image/png', 'image/webp') then raise exception 'Unsupported image type.'; end if;
  if char_length(p_image_base64) > 2_000_000 then raise exception 'That image is too large to check.'; end if;
  select count(*) into user_count from public.ai_usage_log where kind = 'privacy_blur' and user_id = me and created_at >= since;
  if user_count >= 30 then return jsonb_build_object('ok', false, 'error', 'Automatic blur limit reached for today.'); end if;
  select count(*) into global_count from public.ai_usage_log where kind = 'privacy_blur' and created_at >= since;
  if global_count >= 400 then return jsonb_build_object('ok', false, 'error', 'Automatic blur is fully booked for today.'); end if;
  insert into public.ai_usage_log (user_id, kind) values (me, 'privacy_blur');

  resp := private.gemini_generate(jsonb_build_object(
    'contents', jsonb_build_array(jsonb_build_object('parts', jsonb_build_array(
      jsonb_build_object('inlineData', jsonb_build_object('mimeType', p_mime, 'data', p_image_base64)),
      jsonb_build_object('text',
        'Find every human face and every vehicle number plate (licence plate) in this photo. ' ||
        'Return a JSON array; each item has "label" ("face" or "number_plate") and "box_2d", the bounding box as ' ||
        '[ymin, xmin, ymax, xmax] on a 0-1000 scale relative to the image. Make each box slightly larger than the ' ||
        'object so it is fully covered. Return an empty array if there are none.')
    ))),
    'generationConfig', jsonb_build_object(
      'thinkingConfig', jsonb_build_object('thinkingBudget', 0),
      'responseMimeType', 'application/json',
      'responseSchema', jsonb_build_object('type', 'ARRAY', 'items', jsonb_build_object(
        'type', 'OBJECT',
        'properties', jsonb_build_object(
          'label', jsonb_build_object('type', 'STRING', 'enum', jsonb_build_array('face', 'number_plate')),
          'box_2d', jsonb_build_object('type', 'ARRAY', 'items', jsonb_build_object('type', 'INTEGER'))
        ),
        'required', jsonb_build_array('label', 'box_2d')))
    )
  ), 20000);

  if resp.status <> 200 then
    return jsonb_build_object('ok', false, 'error', 'The AI service could not check this photo right now (' || resp.status || ').');
  end if;
  begin
    raw := resp.content::jsonb #>> '{candidates,0,content,parts,0,text}';
    parsed := raw::jsonb;
  exception when others then
    return jsonb_build_object('ok', false, 'error', 'The AI service gave an unreadable answer.');
  end;
  if parsed is null or jsonb_typeof(parsed) <> 'array' then return jsonb_build_object('ok', true, 'regions', out); end if;
  for r in select * from jsonb_array_elements(parsed) loop
    b := r -> 'box_2d';
    if jsonb_typeof(b) = 'array' and jsonb_array_length(b) = 4 and (r ->> 'label') in ('face', 'number_plate') then
      out := out || jsonb_build_object('label', r ->> 'label', 'box', b);
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'regions', out);
end;
$$;
revoke all on function public.detect_privacy_regions(text, text) from public, anon;
grant execute on function public.detect_privacy_regions(text, text) to authenticated;

-- 2. Admin replaces a report's public photo with a blurred copy (uploaded to their own folder in
--    the photos bucket), with an audit entry and a public timeline note.
create or replace function public.admin_replace_issue_photo(p_issue uuid, p_new_path text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  old_path text;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if p_new_path is null or p_new_path !~ ('^' || me::text || '/') then raise exception 'The new photo must be uploaded by you.'; end if;
  select photo_path into old_path from public.issues where id = p_issue;
  if old_path is null then raise exception 'Report not found.'; end if;
  update public.issues set photo_path = p_new_path, updated_at = now() where id = p_issue;
  delete from storage.objects where bucket_id = 'photos' and name = old_path;
  insert into public.issue_timeline (issue_id, status, title, note, actor_id)
  select id, status, 'Photo edited', 'Staff blurred faces or number plates in the photo for privacy.', me from public.issues where id = p_issue;
  insert into public.admin_audit (actor_id, action, target_type, target_id, details)
  values (me, 'issue.photo_blurred', 'issue', p_issue::text, jsonb_build_object('old_path', old_path, 'new_path', p_new_path));
end;
$$;
revoke all on function public.admin_replace_issue_photo(uuid, text) from public, anon;
grant execute on function public.admin_replace_issue_photo(uuid, text) to authenticated;
