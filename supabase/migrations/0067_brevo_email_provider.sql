-- Second email provider. Resend only delivers to the account owner's own address until a domain
-- is verified, which blocked status emails to every other reporter. Brevo's free tier (300 emails
-- a day) delivers to any address from a validated sender email, no domain needed. When a Brevo key
-- is present in the vault it is used; otherwise sending falls back to Resend as before. Set up with:
--   select vault.create_secret('<brevo api key>', 'brevo_key', 'Brevo API key for email alerts');
--   select vault.create_secret('you@gmail.com', 'brevo_from', 'Validated Brevo sender address');
create or replace function private.brevo_key() returns text
language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'brevo_key'
$$;
revoke all on function private.brevo_key() from public, anon, authenticated;

create or replace function private.brevo_from() returns text
language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'brevo_from'
$$;
revoke all on function private.brevo_from() from public, anon, authenticated;

create or replace function private.send_email(p_to text, p_subject text, p_html text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  bkey text := private.brevo_key();
  bfrom text := private.brevo_from();
  rkey text := private.resend_key();
begin
  if p_to is null or p_to = '' then return; end if;
  if bkey is not null and bkey <> '' and bfrom is not null and bfrom <> '' then
    perform net.http_post(
      url := 'https://api.brevo.com/v3/smtp/email',
      headers := jsonb_build_object('Content-Type', 'application/json', 'accept', 'application/json', 'api-key', bkey),
      body := jsonb_build_object(
        'sender', jsonb_build_object('name', 'CivicPulse', 'email', bfrom),
        'to', jsonb_build_array(jsonb_build_object('email', p_to)),
        'subject', left(p_subject, 200), 'htmlContent', p_html)
    );
    return;
  end if;
  if rkey is null or rkey = '' then return; end if;
  perform net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || rkey),
    body := jsonb_build_object('from', private.resend_from(), 'to', jsonb_build_array(p_to), 'subject', left(p_subject, 200), 'html', p_html)
  );
exception when others then
  -- An email that fails to queue should never break whatever the citizen or admin was doing.
  null;
end;
$$;
