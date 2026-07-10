# 11 · Deployment Guide

## Supabase setup (run once, in order, SQL Editor)
1. `supabase/schema.sql` — `app_data` + RLS (live store).
2. `supabase/002_members.sql` — tenant↔owner membership.
3. `supabase/003_push_tokens.sql` — FCM tokens.
4. `supabase/004_saas_core.sql` — relational SaaS schema + RLS + `payment-proofs` bucket. (Idempotent; re-runnable.)
5. `supabase/005_admin_setup.sql` — `admin_setup_attempts`.
6. `supabase/006_invites.sql` — `invites` (tenant invite lifecycle, service-role-write-only) + `resent` status on `tenant_invites` + restrictive `app_data` policies that block writes while `must_change_password` is set. **Not idempotent** (plain `create policy`); run once.
7. `supabase/007_payments.sql` — `pg_upi_settings` + `upi_submissions` (tenant-insert-pending-only RLS) + revokes tenant `payments` blob write + `payment-proofs` storage policies (`can_access_workspace`). **Not idempotent**; run once.
8. `supabase/008_delete_customer.sql` — `admin_delete_customer(uuid)` transactional cascade RPC (service-role only). Idempotent (`create or replace`); safe to re-run.
9. `supabase/009_subscriptions.sql` — adds `starts_at`/`expires_at` to `customers` (+ backfill 30-day window) and makes `my_owner_customer_id` expiry-aware. Idempotent; safe to re-run.
10. `supabase/010_admin_app_data.sql` — platform-admin read policy on `app_data` (admin "View PGs"). Idempotent; safe to re-run.

Auth settings: **Authentication → Providers → Email → turn OFF "Confirm email"** (invited/admin accounts sign in immediately). Optionally set **URL Configuration → Site URL** to the tenant/owner web URL.

## Edge Functions (Dashboard → Edge Functions → Deploy; name must match exactly)
- `push` — `functions/push/index.ts`. Secret: `FIREBASE_SERVICE_ACCOUNT` = full Firebase service-account JSON.
- `invite` — `functions/invite/index.ts`. No extra secret. **Redeploy after Prompt 7** (now handles create/resend/revoke/validate/accept; requires `006_invites.sql`). The app has no client-side fallback — tenant invites fail cleanly if this function is missing.
- `create-admin` — `functions/create-admin/index.ts`. Secrets: `ADMIN_SETUP_KEY` (required), optional `ADMIN_SETUP_KEY_PREVIOUS` (rotation grace), `ADMIN_SETUP_KEY_EXPIRES_AT` (ISO).
- `create-customer` — `functions/create-customer/index.ts`. No extra secret; requires a platform admin caller.
- `delete-customer` — `functions/delete-customer/index.ts`. No extra secret; platform-admin only; requires `008_delete_customer.sql`. Permanently deletes a customer (DB cascade RPC + Storage purge + auth-user deletion).

Auto-injected into every function: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (do not set manually).

## Client config
`lib/src/supabase_config.dart`: `supabaseUrl`, `supabasePublishableKey` (safe to ship), `appWebUrl`, `apkDownloadUrl`. Publishable key only — never the service role.

## Firebase (push)
Android app registered (package `com.example.nestora_pg`); `android/app/google-services.json` present. Service-account JSON goes into the `push` function secret, never the app.

## Build commands
```bash
# Owner/Admin
flutter build web --release -t lib/main_owner.dart
flutter build apk --release -t lib/main_owner.dart
# Tenant
flutter build web --release -t lib/main_tenant.dart
flutter build apk --release -t lib/main_tenant.dart
# Local run
flutter run -t lib/main_owner.dart   # or lib/main_tenant.dart
```
GitHub Actions builds/tests `main.dart` and publishes a release APK on tag `vX.Y.Z` (asset `PG-Management.apk`, served at `apkDownloadUrl`).

## Bootstrap a platform admin
Deploy `create-admin` + set `ADMIN_SETUP_KEY` → in the app: **Admin login → Set up a platform admin** → enter the key. Then admins create customers via **New customer**.

## Release checklist
- [ ] Migrations 1–10 run; email confirmation off; `payment-proofs` bucket present.
- [ ] Auth → URL Configuration: Site URL + Redirect URLs set to the `/PG-Management-app/` path (reset links).
- [ ] All 4 functions deployed; `ADMIN_SETUP_KEY` + `FIREBASE_SERVICE_ACCOUNT` set.
- [x] `flutter analyze` clean; `flutter test` green (101); `dart format` applied. (P11)
- [x] Owner + tenant `flutter build web --release` succeed. (P11)
- [ ] Ship `main_owner`/`main_tenant` builds — `main.dart` is a combined dev/test app (admin now routes to customer management, but keep prod on the split builds).
- [ ] **Blockers before "production multi-tenant":** migrate runtime to relational `customer_id` RLS (P0); backfill `profiles` for legacy tenants so the disabled-customer gate applies (P1). See `09`.
