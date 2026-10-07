-- A reporter who already has an open report of the same category within 50 m was refused outright,
-- with no way past it. That blocks real cases: one person reporting a pipeline leak and, days later,
-- dirty water from a drain on the same street (both "water"). Let them confirm "it is a different
-- problem" the same way other people can; the no-pin identical-title guard stays as it was.
create or replace function public.issues_dedupe() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  n_id uuid; n_ref text; n_author uuid;
  same_person boolean := false;
  v_phone text := regexp_replace(coalesce(new.guest_phone, ''), '[^0-9]', '', 'g');
  v_email text := lower(trim(coalesce(new.guest_email, '')));
begin
  if new.lat is not null then
    select id, ref_no, author_id into n_id, n_ref, n_author from private.nearest_open_issue(new.lat, new.lng, new.category, 50);
  end if;

  -- Guests get a new user id each session, so match them by the hashed phone or email they gave.
  if n_id is not null then
    same_person := n_author = new.author_id;
    if not same_person and public.is_guest(new.author_id) and (v_phone <> '' or v_email <> '') then
      if v_phone ~ '^91[6-9][0-9]{9}$' then v_phone := substr(v_phone, 3); end if;
      same_person := exists (select 1 from public.issue_reporter_contacts c where c.issue_id = n_id
        and (c.phone_hash = private.hash_signal('phone:+91' || v_phone) or c.email_hash = private.hash_signal('email:' || v_email)));
    end if;
  end if;

  -- The same person reporting the same kind of thing at the same spot: refused unless they have
  -- confirmed it is a different problem (a water leak and dirty water are both "water", 50 m apart
  -- is one street), exactly like the check for other people's reports below.
  if same_person and not new.confirmed_distinct then
    raise exception 'DUPLICATE_OWN:%:%', n_ref, n_id
      using hint = 'You have already reported a problem of this kind here. If this one is different, say so and send it.';
  end if;
  -- Without a map pin, catch the same person re-sending an identical title within a week.
  if n_id is null then
    select i.id, i.ref_no into n_id, n_ref from public.issues i
    where i.author_id = new.author_id and i.category = new.category and i.status in ('pending', 'progress')
      and lower(trim(i.title)) = lower(trim(new.title)) and i.created_at > now() - interval '7 days' limit 1;
    if n_id is not null then
      raise exception 'DUPLICATE_OWN:%:%', n_ref, n_id using hint = 'You have already reported this problem.';
    end if;
  -- Someone else already reported it here: they must confirm theirs is a different problem.
  elsif not new.confirmed_distinct then
    raise exception 'DUPLICATE:%:%', n_ref, n_id
      using hint = 'This looks like a problem that has already been reported. Back that report, or confirm yours is different.';
  end if;

  new.confirmed_distinct := false;
  return new;
end;
$$;

