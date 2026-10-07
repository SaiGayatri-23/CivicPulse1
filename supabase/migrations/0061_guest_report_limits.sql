-- Reporting without an account is the main way CivicPulse is meant to be used, and the old guest
-- cap of 3 reports per 30 days per email/phone/device stopped ordinary residents after their third
-- pothole. Loosen it to 10 a day per person and 40 a day per network; the 60-an-hour global guest
-- brake stays. Signed-in users were never capped.
create or replace function public.check_report_limits() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  guest boolean := public.is_guest(new.author_id);
  v_name text := trim(coalesce(new.guest_name, ''));
  v_email text := lower(trim(coalesce(new.guest_email, '')));
  v_phone text := regexp_replace(coalesce(new.guest_phone, ''), '[^0-9]', '', 'g');
  v_device text := private.hash_signal(new.device_id);
  v_ip text := private.hash_signal(private.request_ip());
  h_email text;
  h_phone text;
  recent integer;
  guest_hour integer;
begin
  if guest then
    if char_length(v_name) < 2 or char_length(v_name) > 60 then
      raise exception 'Please enter your name (2 to 60 characters).';
    end if;
    if v_email !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' or char_length(v_email) > 120 then
      raise exception 'Please enter a valid email address.';
    end if;
    if v_phone ~ '^91[6-9][0-9]{9}$' then v_phone := substr(v_phone, 3); end if;
    if v_phone !~ '^[6-9][0-9]{9}$' then
      raise exception 'Please enter a valid 10-digit Indian mobile number.';
    end if;
    v_phone := '+91' || v_phone;
    h_email := private.hash_signal('email:' || v_email);
    h_phone := private.hash_signal('phone:' || v_phone);

    select count(*) into recent from public.issue_reporter_contacts c
    where c.created_at >= now() - interval '1 day'
      and (c.email_hash = h_email or c.phone_hash = h_phone or (v_device is not null and c.device_hash = v_device));
    if recent >= 10 then
      raise exception 'Without an account you can file 10 reports a day, and this email, phone or device has reached that. Please try again tomorrow, or create a free account to report more.';
    end if;

    if v_ip is not null then
      select count(*) into recent from public.issue_reporter_contacts c
      where c.ip_hash = v_ip and c.created_at >= now() - interval '1 day';
      if recent >= 40 then
        raise exception 'Too many reports from your network today. Please try again tomorrow, or create a free account.';
      end if;
    end if;

    select count(*) into guest_hour from public.issue_reporter_contacts c where c.created_at >= now() - interval '1 hour';
    if guest_hour >= 60 then
      raise exception 'Too many reports without an account right now. Please try again shortly, or sign in.';
    end if;

    insert into public.issue_reporter_contacts (issue_id, user_id, name_enc, email_enc, phone_enc, email_hash, phone_hash, device_hash, ip_hash, email_alerts)
    values (new.id, new.author_id, private.enc(v_name), private.enc(v_email), private.enc(v_phone), h_email, h_phone, v_device, v_ip, coalesce(new.guest_email_alerts, false));

    update public.profiles set display_name = v_name where id = new.author_id;
  end if;

  new.guest_name := null;
  new.guest_email := null;
  new.guest_phone := null;
  new.device_id := null;
  new.guest_email_alerts := null;
  return new;
end;
$$;