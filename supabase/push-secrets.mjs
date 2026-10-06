// Fills secrets.sql with the keys from .env.secrets and runs it on the linked project.
// Usage (from the repo root): node supabase/push-secrets.mjs
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';

const env = Object.fromEntries(readFileSync('supabase/.env.secrets', 'utf8').split(/\r?\n/)
  .filter((l) => l.includes('=')).map((l) => [l.split('=')[0].trim(), l.slice(l.indexOf('=') + 1).trim()]));
if (!env.GEMINI_API_KEY || !env.RESEND_API_KEY) { console.log('Fill in both keys in supabase/.env.secrets first.'); process.exit(1); }
const sql = readFileSync('supabase/secrets.sql', 'utf8')
  .replace(/\{\{(\w+)\}\}/g, (_, k) => (env[k] || '').replace(/'/g, "''"));

writeFileSync('supabase/.temp-secrets.sql', sql);
try {
  execSync('npx -y supabase@2.119.0 db query --linked -f supabase/.temp-secrets.sql', { stdio: ['ignore', 'ignore', 'inherit'] });
  console.log('Secrets saved.');
} finally {
  unlinkSync('supabase/.temp-secrets.sql');
}
