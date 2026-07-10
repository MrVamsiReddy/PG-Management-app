# 08 · Architecture Decision Records

Concise ADRs for decisions already made. Status: Accepted unless noted.

## ADR-001 · Keep the `app_data` blob runtime during the SaaS migration
Context: The app shipped on a single-workspace `app_data` blob model (originally mirrored to a local Hive box) before multi-tenancy.
Decision: Introduce the relational customer-scoped schema (`004`) alongside, but keep the owner/tenant runtime on `app_data` so the app stays working end-to-end each phase. The local Hive store and the demo/seed path were later removed, making Supabase `app_data` the single source of truth (cloud-only, no offline cache; collections held in memory only while signed in).
Consequences: Two data models coexist; customer isolation and RLS are still not runtime-enforced (`09` P0 — data flows through `app_data` keyed by `owner_id`, not the relational `customer_id` tables). Revisit: migrate runtime to relational tables. Status: Accepted (transitional).

## ADR-002 · Map-backed localization, not gen_l10n
Decision: `l10n.dart` with a `Map<lang,Map<key,String>>` and a synchronous `LocalizationsDelegate`.
Consequences: No codegen; trivial to extend; English fallback. Only high-visibility surfaces localized so far (`06` P10 pending).

## ADR-003 · Three build surfaces over one AppState
Decision: `main_owner.dart` + `main_tenant.dart` (+ combined `main.dart` for dev/tests) share `bootstrap.dart` and `AppState`; tenant surface imports only tenant screens.
Consequences: Real build-surface isolation for tenant; some tenant UI duplicated (`TenantHome`, `TenantProfileScreen`) to avoid importing owner screens. `main.dart` remains role-impure (`09`).

## ADR-004 · Strict portal login, pure resolver
Decision: `access.dart` holds pure `evaluateProfileAccess`/`portalError`; `AppState` fetches rows and feeds them in. Legacy accounts without a `profiles` row pass through to membership/metadata resolution.
Consequences: Testable without network; back-compatible pre-migration. Trade-off: pass-through skips the disabled-customer check for profile-less tenants (`09`).

## ADR-005 · Server-side admin/customer provisioning via Edge Functions
Decision: Privileged creation (admin, customer+owner) runs in Edge Functions with the service role; setup key lives only in a server secret; timing-safe compare, rotation, expiry, rate-limit.
Consequences: No secrets in the client; no public sign-up. Requires deploying functions + secrets before use.

## ADR-006 · Rent snapshot on payment; rules by sharing type
Decision: `Payment.amount` is copied at due creation and never recomputed; rent by sharing type is set per room (with override). `rent_rules` (effective_from) exists in schema for future history.
Consequences: Changing rent never rewrites past payments. `rent_rules` not yet used by runtime.

## ADR-007 · Partial payments in the core model
Decision: `PaymentStatus{due,partial,paid}` + `paidAmount`; aggregates use `collected`/`balance`.
Consequences: Owner record-payment settles in place; balances tracked. Tenant-side confirmation still Pending (P9).

## ADR-008 · Remove Utility Billing, Attendance, Agreement from UI; keep data internal
Decision: Delete their screens/actions/nav; keep models/seed/fields so stored data still loads.
Consequences: Smaller surface; `Tenant.agreement`, `UtilityBill`, `AttendanceRecord` remain as dormant internal data.

## ADR-009 · Automatic monthly dues generation
Decision: Deterministic-id dues generated at startup for managers; tenant sessions materialise only their own due and never persist owner-wide.
Consequences: No duplicate dues; tenants can't write owner-wide rows.
