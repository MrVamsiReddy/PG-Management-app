# 01 · Project Context

## Overview
PG Management is a role-based platform for managing paying-guest (PG) accommodations in India: properties, rooms/beds, tenants, rent, complaints, notices and visitors. It is evolving from a single-workspace app into a multi-tenant SaaS.

## Business purpose
Let a PG business (a "customer") run its properties end to end, let residents (tenants) see their own rent/notices/complaints/visitors, and let a platform operator (admin) onboard and manage customers.

## Target SaaS model
- Multi-tenant SaaS. Every business record belongs to exactly one **customer**.
- Cloud-only (Supabase). Security enforced by Supabase RLS, not frontend filtering.
- No public sign-up. Accounts are provisioned top-down.

> Reality note: the target model is only partially realised. See `06_PROJECT_STATUS.md` and `09_KNOWN_ISSUES.md` for what is actually enforced today (the live runtime uses the cloud `app_data` blob keyed by `owner_id`, not the relational customer-scoped tables).

## Platform hierarchy
Platform Admin → Customers → (each customer runs the Customer hierarchy).

## Customer hierarchy
Customer → PG → Floor → Room → Bed → Tenant → Payment.

## Role definitions
- **Platform Admin** — global operator (`customer_id = NULL`). Manages customers and platform admins. Not a PG owner.
- **Customer / Owner** — a PG business account. Created only by a platform admin. Manages its own PGs and everything under them.
- **Tenant** — a resident. Login only; created/invited by an owner/admin. Sees only their own data.

Full allowed/forbidden matrix: `04_ROLES_AND_PERMISSIONS.md`.

## Technology stack
- Flutter (Material 3), Dart.
- Supabase (Postgres + Auth + Edge Functions + Storage) — the single source of truth; cloud-only, no local store or offline cache.
- Packages: `supabase_flutter`, `firebase_core`/`firebase_messaging` (FCM push), `flutter_localizations`, `intl`, `image_picker`, `pdf`, `printing`, `share_plus`, `url_launcher`.

## High-level architecture
Three build surfaces over one shared `AppState`: combined (`main.dart`), owner/admin (`main_owner.dart`), tenant (`main_tenant.dart`). Details in `02_ARCHITECTURE.md`.

## Non-negotiable rules (target)
1. Every business record carries a `customer_id`.
2. Security enforced by RLS, not only UI filtering.
3. No demo mode, no public owner sign-up, no local fallback login.
4. New customers start empty (no seed/mock data).
5. Tenant app and owner/admin app are separate surfaces; tenant build excludes owner screens.
6. Tenant can never confirm a payment as paid.

> Rules 1, 2 and 6 are **not yet fully enforced at runtime** — see `09_KNOWN_ISSUES.md`.
