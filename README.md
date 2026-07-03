# PG Management

A mobile-first Flutter platform for PG owners, administrators, and tenants. It ships in a zero-setup local mode backed by Hive, with realistic seeded data and working CRUD/status workflows. Domain data is fully typed (models with IDs, enums and `DateTime`s) behind a repository layer, so a cloud backend can be added without touching the UI.

## Included

- Role-based sign-in and sign-up for Owner, Tenant, and Admin
- PG listings, amenities, property photos entry point, rooms, floors, and bed occupancy
- Tenant onboarding, KYC capture, and rental agreement/e-sign flow
- Rent dues, a working demo checkout that marks rent paid, receipts, and owner-side payment recording
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

`flutter create` adds the native runner projects when cloning this source-only workspace; it preserves the existing `lib/`, `web/`, and package configuration. Select any role on the sign-in screen and use the prefilled demo credentials. Data is stored in the local Hive box `pg_management` and survives app restarts; the store is schema-versioned and reseeds itself after breaking model changes.

## Cloud accounts (Supabase)

The app supports two modes side by side:

- **Demo mode** — no account, data lives in the on-device Hive box, works offline.
- **Cloud accounts** — real email/password sign-up and sign-in via Supabase Auth; each account's data syncs to Postgres and is isolated by row-level security.

Setup for a fresh Supabase project (free tier, no card):

1. Create a project at supabase.com and put its URL and publishable key in `lib/src/supabase_config.dart`. The publishable key is safe to commit — access control lives server-side.
2. Run `supabase/schema.sql` in the dashboard's SQL Editor. It creates the `app_data` table and RLS policies restricting every row to its owner.
3. For frictionless testing, disable email confirmation: Authentication → Sign In / Providers → Email → turn off "Confirm email". Leave it on for production.

The role picked at sign-up (Owner / Tenant / Admin) is stored in user metadata and drives the role-based UI. Data is stored per account as JSONB collections mirroring the local layout; moving to fully relational tables is planned for when cross-account access (owner ↔ tenant linking) lands.

## Safety notes

The payment screen is a Razorpay-style demo UI; connect the official SDK and verify signatures on a server before accepting real money. Document upload and e-sign buttons model their complete user flows but require your chosen storage and e-sign providers for legally binding production use.
