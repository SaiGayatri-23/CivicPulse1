set check_function_bodies = off;
-- The push trigger had the project's own URL hard-coded (0011, 0017), so a copy of this schema in
-- any other Supabase project would post every push to the original project. Read the functions URL
-- from private.app_secrets instead; if it is not set yet, push is skipped (in-app notifications
-- still work). Set it once per project:
--   insert into private.app_secrets (key, value) values ('functions_url', 'https://<ref>.supabase.co/functions/v1')
--   on conflict (key) do update set value = excluded.value;
create or replace function public.push_notification()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  secret text;
  base text;
begin
  if not exists (select 1 from public.push_subscriptions where user_id = new.user_id) then return new; end if;
  select value into secret from private.app_secrets where key = 'push_secret';
  select value into base from private.app_secrets where key = 'functions_url';
  if secret is null or base is null then return new; end if;
  perform net.http_post(
    url := rtrim(base, '/') || '/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', secret),
    body := jsonb_build_object('id', new.id),
    timeout_milliseconds := 5000);
  return new;
end;
$$;
revoke execute on function public.push_notification() from public, anon, authenticated;
