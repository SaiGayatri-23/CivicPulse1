-- Welcome email on registration. With email confirmation switched off (0059/config), a new
-- account received nothing at all, so people had no record that they had registered. Send a short
-- welcome email through the same Resend path as status alerts: when a real account is created
-- (an email address is present; guest sessions have none) and when a guest session is upgraded
-- to an account by adding an email. Queued asynchronously, so sign-up is never slowed down.
create or replace function private.send_welcome_email(p_email text, p_name text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  link text := private.app_url();
  who text := coalesce(nullif(trim(p_name), ''), 'there');
begin
  perform private.send_email(p_email, 'Welcome to CivicPulse, your account is registered',
    '<p>Hello ' || who || ',</p>'
    || '<p>Your CivicPulse account has been created with this email address. You can now report civic problems, '
    || 'back and follow reports, sign petitions and join events.</p>'
    || '<p>Whenever an administrator acts on one of your reports, for example assigns a department, starts work or '
    || 'resolves it, you will receive an email like this one with the new status and a link to the report.</p>'
    || '<p><a href="' || link || '/report">Report a problem</a> &middot; <a href="' || link || '/profile">Open your profile</a></p>'
    || '<p>If you did not create this account, you can ignore this email.</p>');
end;
$$;
revoke all on function private.send_welcome_email(text, text) from public, anon, authenticated;

create or replace function public.welcome_new_account() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Fire once: on creation with an email, or when a guest (no email) gains one.
  if new.email is not null and (tg_op = 'INSERT' or old.email is null) and new.email not like '%@civicpulse.test' then
    perform private.send_welcome_email(new.email, coalesce(new.raw_user_meta_data ->> 'display_name', ''));
  end if;
  return new;
exception when others then
  -- Never let an email problem block account creation.
  return new;
end;
$$;
revoke execute on function public.welcome_new_account() from public, anon, authenticated;
drop trigger if exists on_auth_user_welcome on auth.users;
create trigger on_auth_user_welcome
  after insert or update of email on auth.users
  for each row execute function public.welcome_new_account();
