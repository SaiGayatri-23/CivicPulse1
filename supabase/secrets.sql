select vault.update_secret(id, '{{GEMINI_API_KEY}}') from vault.secrets where name = 'gemini_api_key';
select vault.create_secret('{{GEMINI_API_KEY}}', 'gemini_api_key') where not exists (select 1 from vault.secrets where name = 'gemini_api_key');

select vault.update_secret(id, '{{RESEND_API_KEY}}') from vault.secrets where name = 'resend_key';
select vault.create_secret('{{RESEND_API_KEY}}', 'resend_key') where not exists (select 1 from vault.secrets where name = 'resend_key');
