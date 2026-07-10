# PG Management

A mobile-first Flutter platform for PG owners, administrators, and tenants. It is cloud-only: Supabase is the single source of truth (Auth + Postgres + row-level security), with no local store, demo mode or seeded data — accounts are provisioned top-down and new customers start empty. Domain data is fully typed (models with IDs, enums and `DateTime`s) behind a repository layer.

## Included

- Role-based sign-in for Owner, Tenant, and Admin (no public sign-up; accounts are provisioned top-down)
- PG listings, amenities, property photos entry point, rooms, floors, and bed occupancy
- Tenant onboarding, KYC capture, and rental agreement/e-sign flow
- Monthly rent dues generated automatically, a working demo checkout, PDF receipts, and owner-side payment recording
- Maintenance requests with priorities, technician assignment, and status timeline
- Visitor pre-approvals with approve/decline, check-in, and check-out
- Announcements and push-notification preference
- Tenant attendance with live check-in/check-out and history
- Electricity meter readings and per-bed split billing derived from room occupancy
- Notification centre fed by real in-app actions, tenant search, and a role-aware analytics dashboard
- Adaptive Material 3 UI with bottom navigation on phones and a navigation rail on larger screens

## Run locally

Flutter 3.35+ and Dart 3.3+ are recommended.

```bash
flutter pub get
flutter create --platforms=android,ios,web .
flutter run
```

`flutter create` adds the native runner projects when cloning this source-only workspace; it preserves the existing `lib/`, `web/`, and package configuration.

## Separate apps: Owner/Admin and Tenant

The Owner/Admin and Tenant experiences are separate build surfaces with their own entry points. The tenant build does not include owner/admin screens.

- `lib/main_owner.dart` — Owner/Admin app (owner login, admin login, PG management, tenant creation, reports/settings).
- `lib/main_tenant.dart` — Tenant app (tenant login only; rent, complaints, notices, visitors, profile).
- `lib/main.dart` — combined app used for local development and tests.

Build:

```bash
# Owner/Admin
flutter build web --release -t lib/main_owner.dart
flutter build apk --release -t lib/main_owner.dart

# Tenant
flutter build web --release -t lib/main_tenant.dart
flutter build apk --release -t lib/main_tenant.dart

# Run a surface locally
flutter run -t lib/main_owner.dart
flutter run -t lib/main_tenant.dart
```

## Android release signing & in-app updates

Release APKs are signed with a permanent keystore so a newer APK installs over the old one (no uninstall; data and login kept). On launch the Android app checks the latest GitHub release and, when newer than the installed version, shows an Update prompt that downloads the right APK (Owner/Tenant) for a tap-to-install in-place update.

- The keystore lives at `android/app/release.keystore` with `android/key.properties` (both gitignored — never commit them; losing the keystore breaks in-place updates for existing installs, so back it up).
- CI signing needs four repository secrets (Settings → Secrets and variables → Actions): `ANDROID_KEYSTORE_BASE64` (contents of `android/keystore.base64`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` (values from `android/key.properties`).
- One-time migration: builds before v1.3.0 were debug-signed, so updating from them requires uninstalling once; every update after that is in-place.

## iOS builds (GitHub Actions, no Mac needed)

`.github/workflows/ios.yml` builds unsigned owner + tenant IPAs on a macOS runner: it runs on `v*` tags (IPAs attached to the release next to the APKs) and via manual dispatch (IPAs uploaded as a workflow artifact; pass an existing tag to attach them to that release).

The IPAs are unsigned — App Store/TestFlight distribution needs an Apple Developer account and signing setup. Until then, install on an iPhone by sideloading with a free Apple ID (e.g. Sideloadly or AltStore; apps expire after 7 days), or use the web app as a PWA (Safari → Share → Add to Home Screen).

## Platform admin setup

Platform admins are created through the `create-admin` Edge Function using a server-side setup key. The key is never in the app; it is entered by the person creating the admin and verified server-side with a timing-safe comparison.

1. Run `supabase/004_saas_core.sql` and `supabase/005_admin_setup.sql` in the SQL Editor.
2. Deploy the function: Edge Functions → Deploy → name it exactly `create-admin` → paste `supabase/functions/create-admin/index.ts`.
3. Set the secret (Edge Functions → Secrets): `ADMIN_SETUP_KEY` = a long random string. Optional: `ADMIN_SETUP_KEY_EXPIRES_AT` = an ISO timestamp after which the key stops working.
4. In the app, open **Admin login → Set up a platform admin**, enter name/email/password and the setup key.

Security:
- The key lives only in the Edge Function secret and is compared server-side; it is never returned or logged.
- Failed attempts are rate limited per IP (5 per 15 minutes) via `admin_setup_attempts`; only the IP/email/outcome are recorded, never the attempted key.
- Rotation: set a new `ADMIN_SETUP_KEY`; to allow a grace period, keep the old value in `ADMIN_SETUP_KEY_PREVIOUS` — both are accepted until you remove it.
- Expiry: set `ADMIN_SETUP_KEY_EXPIRES_AT`; after that time every attempt fails.

## Customer management (platform admin)

Signed in as a platform admin (owner/admin app), you manage customers, not PGs directly:

- Create a customer — enters business name, owner name/email, phone. This calls the `create-customer` Edge Function, which creates the customer row and its owner login (temporary password, forced change at first sign-in) and returns the credentials to share. New customers start empty (no PGs, rooms or tenants).
- Enable / disable a customer — a disabled customer immediately blocks its owner and tenants (enforced by RLS).
- View a customer's PGs.

Deploy the function: Edge Functions → Deploy → name it exactly `create-customer` → paste `supabase/functions/create-customer/index.ts`. It requires the caller to be a platform admin.

## Removing a tenant (owner)

Tenants → tenant card → ⋮ → **Remove tenant**. After confirmation the tenant's record and all their data (payments, requests, visitors, notifications) are permanently deleted and their bed is freed. The `remove-tenant` Edge Function then deletes their login, invite/member links, UPI submissions and payment-proof screenshots, and emails the tenant that they are no longer part of the PG and that their data has been permanently deleted (in the owner's app language — English/Hindi/Telugu).

Deploy the function: Edge Functions → Deploy → name it exactly `remove-tenant` → paste `supabase/functions/remove-tenant/index.ts`. For the email, set the `RESEND_API_KEY` secret (free key from resend.com; optional `RESEND_FROM` = a verified sender like `PG Management <you@yourdomain.com>`). Without the secret the removal still works fully — the app just tells the owner no email could be sent. Note: Resend's shared `onboarding@resend.dev` sender only delivers to your own Resend account email; verify a domain to email real tenants.

## Cloud accounts (Supabase)

The app is cloud-only — every session signs in through Supabase Auth and all data lives in Postgres, isolated by row-level security. There is no demo mode or offline store; the app requires a connection. Accounts are provisioned top-down (platform admin → customer/owner → tenant); there is no public sign-up.

Setup for a fresh Supabase project (free tier, no card):

1. Create a project at supabase.com and put its URL and publishable key in `lib/src/supabase_config.dart`. The publishable key is safe to commit — access control lives server-side.
2. Run `supabase/schema.sql` in the dashboard's SQL Editor. It creates the `app_data` table and RLS policies restricting every row to its owner.
3. For frictionless testing, disable email confirmation: Authentication → Sign In / Providers → Email → turn off "Confirm email". Leave it on for production.

The role picked at sign-up (Owner / Tenant / Admin) is stored in user metadata and drives the role-based UI. Data is stored per account as JSONB collections mirroring the local layout; moving to fully relational tables is planned for when cross-account access (owner ↔ tenant linking) lands.

## Safety notes

The payment screen is a Razorpay-style demo UI; connect the official SDK and verify signatures on a server before accepting real money. Document upload and e-sign buttons model their complete user flows but require your chosen storage and e-sign providers for legally binding production use.
