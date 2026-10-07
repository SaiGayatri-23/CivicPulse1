-- People should hear about their report's progress (accepted, in progress, assigned, resolved)
-- without opening the site. Email alerts existed but were off unless switched on in the profile;
-- make them on by default for every account. The profile toggle still turns them off.
alter table public.profiles alter column email_alerts set default true;
update public.profiles set email_alerts = true where not email_alerts;
