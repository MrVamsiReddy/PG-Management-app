# 09 · Known Issues

Severity: P0 blocker · P1 high · P2 medium · P3 low. Grounded in current source.

## Security issues
- **P0 · Runtime not on customer-scoped RLS.** Owner/tenant data flows through `app_data` (`repositories.dart` `SupabaseRepository`), keyed by `owner_id`; `customer_id` is JSON metadata only. The `004` relational RLS is unused at runtime. Fix: migrate reads/writes to the relational tables. (The local Hive store and demo/seed path have been removed — the app is now cloud-only — but this does not by itself move enforcement onto the relational tables.)
- **P0 · Tenant can mark rent PAID.** `finance_screens.dart` `_paymentFlow` → `app_state.payRent` sets `status=paid`. Must become a proof submission; only owner confirms (P9).
- **P1 · Disabled customer does not block tenants.** Invited tenants have no `profiles` row → `_fetchAccessGate` pass-through skips the `customers.status` check. Fix: create a `profiles` row per tenant (P7) so the gate applies.
- **P2 · Intra-workspace tenant isolation is client-side.** Tenant reads the whole workspace blob; `visibleNotifications`/`tenantPayments`/`visibleAnnouncements` filter in Dart, not via RLS.
- **P2 · `must_change_password` not server-enforced.** Only `SetPasswordScreen` blocks the UI; the API would serve a temp-password session.

## Missing functionality (Pending — see 06)
- P1 · Tenant invite tokens/states + expiry/revoke (P7).
- P1 · Manual UPI submit/confirm/reject flow (P9).
- P1 · Audit log writes + viewers (P8).
- P2 · Admin "view customer PGs" returns empty — `loadCustomerPgNames` reads relational `pgs` the app never writes.
- P2 · Full localization (P10).

## Incorrect permissions
- P1 · `main.dart` (combined app) routes a platform admin into the PG `HomeShell` (PG operations) — admin should be customer-management only. Fix: restrict/retire `main.dart` for production; ship `main_owner.dart`/`main_tenant.dart`.

## Technical debt
- P1 · Two parallel data models (`app_data` blob live vs relational unused).
- P2 · `AppState.customerId` falls back to `_workspaceOwnerId ?? ''`; records can be stamped with a literal `''` before a customer is resolved.
- P3 · Signed-out preferences don't persist — `language`/`pushEnabled` are session-scoped now (no local store to hold them across launches).
- P3 · Duplicated tenant UI (`TenantHome`, `TenantProfileScreen`) vs owner equivalents (deliberate, ADR-003).

## Performance
- P3 · Whole collections saved as one JSONB blob per `app_data` key on every change; photos stored inline (base64). Fine at small scale; won't scale per-customer.

## Future improvements
- Session revocation on customer disable (currently blocks at start/refresh only).
- Move rent history to `rent_rules` (effective dates) once runtime is relational.
- Localize Edge-Function messages via stable error codes (P10).
