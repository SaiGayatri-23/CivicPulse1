select vault.update_secret(id, '{{GEMINI_API_KEY}}') from vault.secrets where name = 'gemini_api_key';
select vault.create_secret('{{GEMINI_API_KEY}}', 'gemini_api_key') where not exists (select 1 from vault.secrets where name = 'gemini_api_key');

select vault.update_secret(id, '{{RESEND_API_KEY}}') from vault.secrets where name = 'resend_key';
select vault.create_secret('{{RESEND_API_KEY}}', 'resend_key') where not exists (select 1 from vault.secrets where name = 'resend_key');

-- Optional: Brevo (delivers to any address from a validated sender; leave blank to keep using Resend)
select vault.update_secret(id, '{{BREVO_API_KEY}}') from vault.secrets where name = 'brevo_key' and '{{BREVO_API_KEY}}' <> '';
select vault.create_secret('{{BREVO_API_KEY}}', 'brevo_key') where '{{BREVO_API_KEY}}' <> '' and not exists (select 1 from vault.secrets where name = 'brevo_key');
select vault.update_secret(id, '{{BREVO_FROM}}') from vault.secrets where name = 'brevo_from' and '{{BREVO_FROM}}' <> '';
select vault.create_secret('{{BREVO_FROM}}', 'brevo_from') where '{{BREVO_FROM}}' <> '' and not exists (select 1 from vault.secrets where name = 'brevo_from');
