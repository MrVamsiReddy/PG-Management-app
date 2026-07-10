# 06 · Project Status

Roadmap = `app improvements.md` (Prompts 1–11). Details of each area live in `03`/`04`/`05`; issues in `09`.

## Completed (Prompts 1–11)
- **P1 Data model** — `customer_id` on all business models; relational schema + RLS (`004`); SaaS mirror models (`saas_models.dart`). Schema defined; not wired to owner/tenant runtime.
- **P2 Strict login** — portal login (owner/tenant/admin), profile+customers gate, disabled/wrong-portal blocked, no offline fallback, demo mode removed from UI.
- **P3 App split** — `main_owner.dart` / `main_tenant.dart` + shared `bootstrap.dart`; tenant build has no owner screens; `main.dart` kept as combined dev/test app.
- **P4 Admin setup key** — `create-admin` fn (server key, timing-safe, rotation, expiry, rate limit) + `005` table + `AdminSetupScreen`.
- **P5 Customer management** — `create-customer` fn + `CustomerManagementScreen` (create/enable/disable/view-PGs) + owner empty-state.
- **P6 PG onboarding wizard** — `PgSetupWizard` + `createProperty` + structure guards + rent snapshot.
- **P7 Tenant invites** — `invite` fn rewritten (create/resend/revoke/validate/accept), `006_invites.sql` (`invites` table: one-time token, expiry, pending/accepted/expired/revoked/resent; service-role writes only), invited tenants get a `profiles` row when the owner has a resolved customer, invite message builder (`invite_message.dart`), resend/revoke owner UI, expired/revoked invite blocks tenant first sign-in, `must_change_password` now blocks `app_data` writes at the DB (restrictive RLS) and the app refreshes the JWT after the change.
- **P8 Audit logs** — `audit_logs` table + RLS already in `004` (admin all, owner own-customer read+append, tenant none; fields incl. `ip`/`user_agent`). Writes wired: edge functions (`create-admin`→admin_created, `create-customer`→customer_created+owner_created, `invite`→tenant_invited/resent/revoked) via service role; app-side `_audit()` (best-effort insert) on customer enable/disable, pg_created, room_created/removed/beds_changed, rent_changed, tenant_assigned, payment_recorded. Viewer `AuditLogScreen` (admin appbar → all; owner settings → own). `AuditLog.fromRow` maps DB columns.
- **P9 Manual UPI payments** — `007_payments.sql` (`pg_upi_settings`, `upi_submissions` with tenant-insert-pending-only + owner/admin read RLS; drops tenant `payments` blob write; workspace-scoped `payment-proofs` storage). Runtime models `UpiSettings`/`UpiSubmission`; `AppState` submit/confirm/reject/settings + `paymentStatusKey`/`canSubmit`/`duplicateOf`; `payRent` removed. UI `upi_screens.dart` (tenant pay-via-UPI + UTR/screenshot submit, owner `PaymentReviewScreen`, `UpiSettingsScreen`). Audit payment_submitted/confirmed/rejected. Localized en/hi/te.
- **P10 Full localization** — language now **persists** (`shared_preferences`, `loadLanguage` at bootstrap). Localized auth (portals/login/set-password/admin-setup), dashboard, PG wizard, tenant invite dialog on top of the existing nav/settings/profile/announcements/UPI. `signInCloud` returns `code:*`; `AppLocalizations.error(code)` maps backend/auth codes to localized text. en/hi/te expanded (~90 keys). Not-yet-covered: some secondary ops/community/room-detail strings.
- **P11 Production QA** — checklist verified against source (see below); fixed the receipt PDF footer ("demo receipt" → "not a valid tax document"). `dart format` clean, `flutter analyze` clean, `flutter test` 101 passing, and **both `flutter build web --release` (owner + tenant) succeed**. Remaining production blockers are the pre-existing P0/P1 items in `09` (runtime still on `app_data`/`owner_id`, not relational `customer_id` RLS; legacy tenants bypass the disabled-customer gate).

## Post-P11 improvements (in progress, one task at a time)
- **Customer deletion (done)** — platform admin can permanently delete a customer from `CustomerManagementScreen` (delete icon + confirm dialog). `AppState.deleteCustomer` → `delete-customer` Edge Function (platform-admin only) → `admin_delete_customer(target)` RPC in `008_delete_customer.sql`: a single-transaction plpgsql cascade over app_data/members/invites/pg_upi_settings/upi_submissions/push_tokens/audit_logs/profiles and the `customers` row (which cascades all 004 relational tables). The function then purges the customer's `payment-proofs` Storage folder and deletes every auth user (owner + tenants). RPC is service-role-only (`revoke ... from public, authenticated`). UI removes the row on success.
- **PG creation simplified (done)** — `PgSetupWizard` is now a single form collecting only PG name, address and amenities (basic info); the rent-by-sharing and floors/rooms/beds steps were removed. `createProperty` accepts optional `specs` (defaults to empty) so a PG can be created with **no rooms** — rooms/sharing/rent are configured later (onboarding / Rooms & Beds). Rent and sharing no longer appear during PG creation.
- **Tenant onboarding sets room pricing (done)** — the onboarding sheet now selects PG, Floor, Room (existing or "＋ New room"), Sharing Type, Current Room Rent and Bed. `AppState.ensureRoom(...)` creates the room (sharing type = beds, current rent) when new — idempotent per room number in a PG, and bumps the PG bed count; existing rooms show inherited sharing/rent. The tenant inherits the room's rent as their first due (snapshot). `Room.type` now covers 1–4 sharing.
- **Room pricing model (done/verified)** — Room stores sharing type (`Room.sharingType` = `beds`) + current `rent`; Tenant stores `roomId` + `bed`; Payment stores the rent snapshot (`amount`, fixed at creation by `generateMonthlyDues`, which is idempotent per tenant+period). `setRoomRent` mutates only the room, so a rent change flows into **future** dues (next period / newly assigned tenants) while existing/historical dues keep their snapshot. Also hardened `_id()` with a monotonic counter so ids stay unique under a coarse clock (two rapid onboardings no longer collide).

## In progress
- Improvements batch tasks 5–9 (password mgmt, subscriptions, dashboard, navigation, rooms/beds) — pending, executed one at a time.

## P11 production checklist (verified 2026-07-10)
- ✅ No demo/local/offline code, no seed/mock path (Hive + demo removed; only stray comments remained).
- ✅ No public owner signup ("Accounts are created by your administrator" — portal login only).
- ✅ Separate owner (`main_owner`) & tenant (`main_tenant`) apps; tenant build imports no owner/admin screen files (`home_shell`/`property_screens`/`admin_customers`/`pg_wizard` absent).
- ✅ RLS enabled on every table (`schema`+`002`–`007`); admin setup key server-side + timing-safe + rotation/expiry/rate-limit.
- ✅ `must_change_password` enforced (client `SetPasswordScreen` + restrictive `app_data` write policies in `006`).
- ✅ Invite lifecycle (pending/accepted/expired/revoked/resent, single-use) + audit logging (incl. payment_submitted/confirmed/rejected).
- ✅ Rent history preserved; occupied-structure edits blocked; tenant cannot mark paid; UPI return never auto-confirms; payment-proofs storage workspace-scoped; duplicate UTR detection.
- ⚠️ Localization core/tested flows done; a few secondary owner/ops screens still English.
- ❌ **Blockers (P0/P1, see `09`):** runtime not on relational `customer_id` RLS (isolation is `owner_id`-scoped); legacy tenants (no `profiles` row) bypass the disabled-customer gate.

## Known issues
See `09_KNOWN_ISSUES.md` (P0: runtime on the `app_data` blob keyed by `owner_id`, not relational RLS. Tenant-marks-paid resolved in P9).

## Technical debt
- Two parallel data models (`app_data` blob live vs relational unused).
- (resolved) `main.dart` now routes admin to customer management, not PG operations.
- Localization: core + tested flows done (P10); a few secondary owner/ops screens still hold English strings.

## Recently done (cloud-only)
Removed the local Hive store, the demo/seed path (`_seed`, `debugSeedDemoData`), and the `cloudMode`/`'demo'` fallbacks. Supabase `app_data` is now the single source of truth; the app requires a connection and has no offline cache. `pushEnabled` is session-scoped; **`language` now persists** on-device via `shared_preferences` (P10). This satisfies the "No Demo / no local fallback / empty new customers" prerequisites but does **not** move enforcement onto the relational tables (still P0 below).

## Next recommended phase
Before Prompts 8–11 add more features on the unenforced foundation, migrate the owner/tenant runtime from the `app_data` blob onto the relational `customer_id`-scoped tables so `004` RLS becomes the enforcement boundary, and make `payRent` a submission (not a paid-mark). Then P9/P8 land on solid ground.

## Test status
`test/app_test.dart` — 106 passing; `flutter analyze` clean; `dart format` applied repo-wide; owner + tenant `flutter build web --release` succeed. See `10_TESTING_GUIDE.md`.
