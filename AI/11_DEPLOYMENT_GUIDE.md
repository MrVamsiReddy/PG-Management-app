# 11 · Deployment Guide

## Supabase setup (run once, in order, SQL Editor)
1. `supabase/schema.sql` — `app_data` + RLS (live store).
2. `supabase/002_members.sql` — tenant↔owner membership.
3. `supabase/003_push_tokens.sql` — FCM tokens.
4. `supabase/004_saas_core.sql` — relational SaaS schema + RLS + `payment-proofs` bucket. (Idempotent; re-runnable.)
5. `supabase/005_admin_setup.sql` — `admin_setup_attempts`.

Auth settings: **Authentication → Providers → Email → turn OFF "Confirm email"** (invited/admin accounts sign in immediately). Optionally set **URL Configuration → Site URL** to the tenant/owner web URL.

## Edge Functions (Dashboard → Edge Functions → Deploy; name must match exactly)
- `push` — `functions/push/index.ts`. Secret: `FIREBASE_SERVICE_ACCOUNT` = full Firebase service-account JSON.
- `invite` — `functions/invite/index.ts`. No extra secret.
- `create-admin` — `functions/create-admin/index.ts`. Secrets: `ADMIN_SETUP_KEY` (required), optional `ADMIN_SETUP_KEY_PREVIOUS` (rotation grace), `ADMIN_SETUP_KEY_EXPIRES_AT` (ISO).
- `create-customer` — `functions/create-customer/index.ts`. No extra secret; requires a platform admin caller.

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
- [ ] Migrations 1–5 run; email confirmation off.
- [ ] All 4 functions deployed; `ADMIN_SETUP_KEY` + `FIREBASE_SERVICE_ACCOUNT` set.
- [ ] `flutter analyze` clean; `flutter test` green.
- [ ] Ship `main_owner`/`main_tenant` builds — **not** `main.dart** (combined app leaks admin PG ops, `09`).
- [ ] Review `09` P0/P1 before treating as production multi-tenant.
