# 06 · Project Status

Roadmap = `app improvements.md` (Prompts 1–11). Details of each area live in `03`/`04`/`05`; issues in `09`.

## Completed (Prompts 1–6)
- **P1 Data model** — `customer_id` on all business models; relational schema + RLS (`004`); SaaS mirror models (`saas_models.dart`). Schema defined; not wired to owner/tenant runtime.
- **P2 Strict login** — portal login (owner/tenant/admin), profile+customers gate, disabled/wrong-portal blocked, no offline fallback, demo mode removed from UI.
- **P3 App split** — `main_owner.dart` / `main_tenant.dart` + shared `bootstrap.dart`; tenant build has no owner screens; `main.dart` kept as combined dev/test app.
- **P4 Admin setup key** — `create-admin` fn (server key, timing-safe, rotation, expiry, rate limit) + `005` table + `AdminSetupScreen`.
- **P5 Customer management** — `create-customer` fn + `CustomerManagementScreen` (create/enable/disable/view-PGs) + owner empty-state.
- **P6 PG onboarding wizard** — `PgSetupWizard` + `createProperty` + structure guards + rent snapshot.

## In progress
- None (each prompt shipped whole). Cross-cutting gap: runtime not migrated to relational tables.

## Pending (Prompts 7–11, not started)
- **P7** Tenant invite tokens + states (pending/accepted/expired/revoked) + profiles row for tenants.
- **P8** Audit logs (writes + admin/owner viewers).
- **P9** Manual UPI payment: settings, tenant submit + proof upload, owner confirm/reject, tenant-can't-mark-paid.
- **P10** Full localization (all screens; currently only nav/settings/profile/announcements are localized) + backend error-code → localized string mapping.
- **P11** Production safety QA + owner/tenant web/APK release builds.

## Known issues
See `09_KNOWN_ISSUES.md` (P0: runtime on the `app_data` blob keyed by `owner_id`, not relational RLS; tenant marks payment paid).

## Technical debt
- Two parallel data models (`app_data` blob live vs relational unused).
- `main.dart` combined app grants admin PG operations.
- Localization partial; some Edge-Function messages are English strings mapped client-side.

## Recently done (cloud-only)
Removed the local Hive store, the demo/seed path (`_seed`, `debugSeedDemoData`), and the `cloudMode`/`'demo'` fallbacks. Supabase `app_data` is now the single source of truth; the app requires a connection and has no offline cache. Preferences (`language`/`pushEnabled`) are session-scoped. This satisfies the "No Demo / no local fallback / empty new customers" prerequisites but does **not** move enforcement onto the relational tables (still P0 below).

## Next recommended phase
Before Prompts 7–11 add more features on the unenforced foundation, migrate the owner/tenant runtime from the `app_data` blob onto the relational `customer_id`-scoped tables so `004` RLS becomes the enforcement boundary, and make `payRent` a submission (not a paid-mark). Then P9/P8/P7 land on solid ground.

## Test status
`test/app_test.dart` — 75 passing; `flutter analyze` clean. See `10_TESTING_GUIDE.md`.
