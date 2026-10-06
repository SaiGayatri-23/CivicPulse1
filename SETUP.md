# CivicPulse: finishing the Supabase setup

New Supabase project: `fotpcmvojzhptjuoorou` (Singapore, chelukapallys@gmail.com account).

Already done: database (all migrations), storage buckets, nightly cleanup job, push-notification
keys, push function, and `web/.env` pointing at this project.

Run every command in **PowerShell** from the project folder:

```
cd D:\Work\CivicPulse
```

---

## Step 1. Add the Gemini and Resend keys

These power the AI features and email alerts.

1. Get the keys:
   - **Gemini:** https://aistudio.google.com/apikey → *Create API key*
   - **Resend:** https://resend.com/api-keys → *Create API Key*
   - (Or copy them from the old project: devi7911 account → old project → Integrations → Vault → Secrets → eye icon.)

2. Open the secrets file:
   ```
   notepad supabase\.env.secrets
   ```

3. Paste each key right after the `=` sign (no quotes, no spaces):
   ```
   GEMINI_API_KEY=AIza...
   RESEND_API_KEY=re_...
   ```

4. **Save** (Ctrl+S) and close Notepad.

5. Send the keys to Supabase:
   ```
   node supabase/push-secrets.mjs
   ```
   It should print **Secrets saved.**
   If it says *Fill in both keys...*, the file was not saved; repeat steps 2 to 4.

This file is git-ignored, so the keys are never committed. To change a key later, edit the file and run step 5 again.

---

## Step 2. Turn on guest reporting

Without this, people who are not signed in cannot report a problem.

1. Supabase dashboard → **Authentication** → **Sign In / Providers**.
2. Switch on **Allow anonymous sign-ins**.
3. Click **Save**.

---

## Step 3. Set the app address

This makes the links in sign-up and password-reset emails open the app.

1. Supabase dashboard → **Authentication** → **URL Configuration**.
2. **Site URL:** `http://localhost:5180`
3. **Redirect URLs** → *Add URL*: `http://localhost:5180/**`
4. Click **Save**.

When the app is deployed to a real web address, replace `http://localhost:5180` with that address in both places.

---

## Step 4. Create your admin account

1. Start the app:
   ```
   npm --prefix web run dev
   ```
2. Open http://localhost:5180, click **Sign in → Create account**, and sign up with your email.
3. Confirm the account from the email Supabase sends you.
4. Make yourself an admin (replace the email with yours):
   ```
   npx -y supabase@2.119.0 db query --linked "update public.profiles set role = 'admin' where id = (select id from auth.users where email = 'you@example.com')"
   ```
5. Sign out and sign in again. The admin console now appears.

---

## Optional (can wait)

| What | Why | Where |
|---|---|---|
| Google sign-in | Lets people sign in with Google | Authentication → Sign In / Providers → Google, then set `VITE_AUTH_GOOGLE=true` in `web/.env` |
| CAPTCHA (Cloudflare Turnstile) | Blocks bots on guest reports | Authentication → Attack Protection, then set `VITE_TURNSTILE_SITE_KEY` in `web/.env` |
| Own email sending address | Without it, emails come from `onboarding@resend.dev` and Resend only delivers to your own Resend account email | Verify a domain in Resend, then add `RESEND_FROM=CivicPulse <alerts@yourdomain>` to `supabase\.env.secrets`, add a matching line to `supabase\secrets.sql`, and run step 1.5 again |

---

## If something goes wrong

| Problem | Fix |
|---|---|
| `Fill in both keys...` | The secrets file is empty or not saved. Redo step 1. |
| `Cannot find project ref` / not linked | `npx -y supabase@2.119.0 login`, then `npx -y supabase@2.119.0 link --project-ref fotpcmvojzhptjuoorou` |
| Guests see an error when reporting | Step 2 was not saved. |
| Email links open the wrong page | Check the Site URL and Redirect URLs in step 3. |
| AI says "used up for today" | The free Gemini plan allows about 20 requests a day. It resets daily. |
