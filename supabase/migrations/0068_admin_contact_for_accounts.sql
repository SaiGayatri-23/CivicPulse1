-- "Show reporter contact" only covered guest reports (the details typed into the form). For
-- reports filed from an account it showed nothing, so staff could not phone or email the reporter.
-- Return the account holder's name, sign-in email and profile phone as well, logged the same way.
drop function if exists public.admin_reporter_contacts(uuid[]);
create function public.admin_reporter_contacts(p_issues uuid[])
returns table (issue_id uuid, name text, email text, phone text, guest boolean)
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if coalesce(array_length(p_issues, 1), 0) > 50 then raise exception 'At most 50 reports at a time'; end if;
  perform public.log_admin('view_contact', 'issues', null, jsonb_build_object('issues', to_jsonb(p_issues)));
  return query
  select c.issue_id, private.dec(c.name_enc), private.dec(c.email_enc), private.dec(c.phone_enc), true
  from public.issue_reporter_contacts c where c.issue_id = any (p_issues)
  union all
  select i.id, p.display_name, au.email::text, pp.phone, false
  from public.issues i
  join public.profiles p on p.id = i.author_id
  join auth.users au on au.id = i.author_id
  left join public.profile_private pp on pp.id = i.author_id
  where i.id = any (p_issues)
    and not public.is_guest(i.author_id)
    and not exists (select 1 from public.issue_reporter_contacts c where c.issue_id = i.id);
end;
$$;
revoke all on function public.admin_reporter_contacts(uuid[]) from public, anon;
grant execute on function public.admin_reporter_contacts(uuid[]) to authenticated;
