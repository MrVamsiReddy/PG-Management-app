# 05 · Business Rules

Enforced in current code unless marked Pending. Roles → `04`; schema → `03`.

## Customer lifecycle
- Customers and their owner login are created only by a platform admin via `create-customer` (verifies caller `platform_admin`). Owner gets a temp password + `must_change_password=true` metadata + a `profiles` row (role=owner, customer_id). ✅
- New customers start empty — the function inserts no PGs/rooms/tenants. ✅
- Enable/disable via `setCustomerStatus` (updates `customers.status`). Owners with a profile are then blocked by the login gate. ✅ (tenants gap → `09`).
- `must_change_password` is enforced client-side (`SetPasswordScreen` blocks the app) and server-side for writes (`006` restrictive `app_data` policies; app refreshes the JWT after the change). ✅
- **Password flows (improvement 5):** first login requires **temporary + new + confirm** — `SetPasswordScreen` shows a temporary-password field that `changePassword(currentPassword:)` re-validates (via re-auth) before saving the new one; access is gated (`needsPasswordSet`) until it succeeds. Password reset uses `resetPasswordForEmail(redirectTo: appWebUrl)`; the `passwordRecovery` auth event sets `passwordRecovery` → the same set-password screen (new + confirm only, no temp field). Both `mustChangePassword` and `passwordRecovery` gate every app entry point. ✅

## PG hierarchy
- Owner creates a PG via `PgSetupWizard` → `AppState.createProperty(name, address, amenities)` — **only** name/address/basic info; no rent or sharing type. `specs` is optional (defaults to empty) so the PG starts with **no rooms**; rooms/sharing/rent are added later during tenant onboarding or on the Rooms & Beds screen. Stamped with `customerId`, set active. ✅
- The live `Room` model carries `floor` (int), `beds` (count), sharing type (= beds) and `rent`. Separate `floors`/`beds` relational rows are **not** created (schema B unused). ⚠️
- Multiple PGs per owner supported; `activePg`/`selectPg` scope all owner screens. ✅

## Bed / room assignment (onboarding sets room pricing)
- Onboarding (`TenantsScreen._onboard`) collects PG, Floor, Room (existing or new), Sharing Type, Current Room Rent, Bed and tenant details. A new room is created via `AppState.ensureRoom(pgId, floor, roomNumber, sharingType, rent)` (sharing type = beds; idempotent per room number in a PG; bumps the PG bed count); an existing room's sharing/rent are shown as **inherited**. The tenant then inherits the room's current rent as their first due (snapshot). ✅
- `onboardTenant(name, phone, roomId, bed, kycDoc)` validates: name present, 10-digit phone, bed label present, room not full, bed label unique in room. Increments room + property occupancy. ✅
- Structure guards: `removeRoom` blocks rooms with active tenants; `setRoomBeds` blocks reducing below occupancy (`max(stored occupied, tenants in room)`); `setRoomRent` changes rent. ✅

## Rent
- Rent by sharing type entered in the wizard; each room stores its rent (snapshot / override). ✅
- `generateMonthlyDues` creates the current month's `due` per tenant at the room's rent, idempotent (deterministic id `pay-YYYY-M-tenantId`, `unique(tenant_id, period)` in relational schema). Runs at startup for managers; a tenant session only materialises its own due, never persists owner-wide. ✅
- **Rent history preserved:** `Payment.amount` is fixed at creation; changing a room's rent later never rewrites existing dues/payments. ✅

## Payment workflow (P9, current)
- Owner `recordPayment` settles the matching current-month due in place (full→paid, part→partial) or creates a standalone advance row; no duplicate current-month rows. ✅
- Partial payments supported (`paidAmount`, `collected`, `balance`, `Partial` status). ✅
- **Manual UPI (Prompt 9):** owner sets UPI id / payee / enable per PG (`pg_upi_settings`, `UpiSettingsScreen`). Tenant views dues, taps Pay via UPI (`upi://` external app), then submits a UTR + optional screenshot → a `upi_submissions` row with status `pending_confirmation`. Returning from the UPI app confirms nothing. Owner reviews (`PaymentReviewScreen`) with tenant/amount/month/UTR/screenshot/time and Confirms (→ due marked paid, `confirmed_by`/`confirmed_at`) or Rejects (mandatory reason → status `rejected`, tenant may resubmit). ✅
- **Tenant can never mark paid:** `payRent` was removed; tenants have no UPDATE policy on `upi_submissions` and (via `007`) can no longer write the `app_data` payments blob. Only owner confirmation flips a due to paid. ✅
- Derived status shown = due · overdue · pending_confirmation · paid · rejected (`AppState.paymentStatusKey`). Duplicate `amount`+`utr` in a workspace surfaces an owner warning (`duplicateOf`). Screenshots live in the `payment-proofs` bucket at `{owner}/{pg}/{tenant}/{payment}/…`. Audit: `payment_submitted`/`payment_confirmed`/`payment_rejected`. ✅

## Invite workflow (P7, current)
- Only owners create tenant logins, via `inviteTenant`/`resendInvite`/`revokeInvite` → the `invite` Edge Function (actions create/resend/revoke/validate/accept). No client-side fallback. ✅
- `create`: tenant auth user with temp password + metadata (`role=tenant`, `must_change_password=true`, `customer_id`, `tenant_id`, `pg_id`, `room_id`, `bed_id`), `members` link, `profiles` row (when the owner has a resolved customer), and an `invites` row: one-time token, `expires_at` = 7 days. ✅
- Lifecycle: pending → accepted (tenant sets own password) / expired (past `expires_at`) / revoked (owner cancels; unused temp password scrambled) / resent (superseded by a new invite, which regenerates the temp password only while onboarding is incomplete). Single-use enforced by the guarded pending→accepted transition. ✅
- First tenant sign-in on a temp password calls `validate`: an expired/revoked invite blocks the login (`_enterCloud`). After the password change the app refreshes the JWT and calls `accept`. ✅
- Share message (`invite_message.dart`): email, temp password (only when just generated — never redisplayed), APK link, web login link, invite link, password-change instructions, expiry. Temp passwords are never logged. ✅
- `must_change_password` enforced client-side (`SetPasswordScreen`) **and** backend-side (restrictive `app_data` write policies in `006`). ✅

## Notifications & announcements
- In-app notifications are role-scoped (`visibleNotifications`: tenant sees own + workspace; managers see managerial + active-PG). ✅
- Announcements have an audience (all / specific PG); tenants see only their PG's + global (`visibleAnnouncements`). ✅
- Push (FCM) via `push` function respects notification scope and the `pushEnabled` preference. ✅

## Audit logging (P8)
- `audit_logs` (in `004`): id, customer_id (nullable), actor_user_id, actor_role, action, entity_type, entity_id, before_json, after_json, ip, user_agent, created_at. Append-only. ✅
- Written by: edge functions with the service role — `create-admin` (admin_created), `create-customer` (customer_created, owner_created), `invite` (tenant_invited/tenant_invite_resent/tenant_invite_revoked) — and app-side `AppState._audit()` (best-effort, non-blocking) on customer_enabled/disabled, pg_created, room_created/removed/beds_changed, rent_changed, tenant_assigned, payment_recorded. ✅
- payment_submitted/confirmed/rejected reserved for the P9 UPI flow. App-side owner logs depend on the owner having a resolved `customer_id` (RLS owner-insert requires `customer_id = my_owner_customer_id()`); legacy owners without a profile write nothing. ⚠️
- Permissions (RLS): platform admin → all; owner → own customer read+append; tenant → none. Viewer: `AuditLogScreen` (admin appbar, owner settings). ✅

## Localization (P10)
- Map-backed `AppLocalizations.t(key)` over `_strings` (en/hi/te); English is source + fallback. No ICU/placeholders — dynamic values are concatenated in Dart. ✅
- Language **persists on-device** via `shared_preferences` (`AppState.loadLanguage` at bootstrap, `setLanguage` writes). Chosen language survives restarts. ✅
- Localized flows: navigation, settings, profile, announcements, UPI payment (P9), **auth (portals/login/set-password/admin-setup), dashboard, PG wizard, tenant invite dialog**, plus status/error strings. ✅
- Backend/auth **error codes → localized text**: `signInCloud` returns `code:network|bad_credentials|generic`; `AppLocalizations.error(code)` maps them (and admin/invite `code:*`), passing through already-human strings. ✅
- ⚠️ Not every secondary owner/ops screen is fully delocalized yet (some operations/community/room detail strings remain English); the tested and highest-traffic flows are done.

## Disabled customer behaviour
See `04` and `09`: owners blocked, profile-less tenants not blocked.
