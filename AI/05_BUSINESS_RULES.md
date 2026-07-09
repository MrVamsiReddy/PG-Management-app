# 05 · Business Rules

Enforced in current code unless marked Pending. Roles → `04`; schema → `03`.

## Customer lifecycle
- Customers and their owner login are created only by a platform admin via `create-customer` (verifies caller `platform_admin`). Owner gets a temp password + `must_change_password=true` metadata + a `profiles` row (role=owner, customer_id). ✅
- New customers start empty — the function inserts no PGs/rooms/tenants. ✅
- Enable/disable via `setCustomerStatus` (updates `customers.status`). Owners with a profile are then blocked by the login gate. ✅ (tenants gap → `09`).
- `must_change_password` is enforced **client-side** only (`SetPasswordScreen` blocks the app); not server-enforced. ⚠️

## PG hierarchy
- Owner builds a PG via `PgSetupWizard` → `AppState.createProperty(name, address, amenities, specs)`. Creates a `Pg` and its `Room`s in the live model, stamped with `customerId`, and sets it active. ✅
- The live `Room` model carries `floor` (int) and `beds` (count). Separate `floors`/`beds` relational rows are **not** created (schema B unused). ⚠️
- Multiple PGs per owner supported; `activePg`/`selectPg` scope all owner screens. ✅

## Bed / room assignment
- `onboardTenant(name, phone, roomId, bed, kycDoc)` validates: name present, 10-digit phone, bed label present, room not full, bed label unique in room. Increments room + property occupancy. ✅
- Structure guards: `removeRoom` blocks rooms with active tenants; `setRoomBeds` blocks reducing below occupancy (`max(stored occupied, tenants in room)`); `setRoomRent` changes rent. ✅

## Rent
- Rent by sharing type entered in the wizard; each room stores its rent (snapshot / override). ✅
- `generateMonthlyDues` creates the current month's `due` per tenant at the room's rent, idempotent (deterministic id `pay-YYYY-M-tenantId`, `unique(tenant_id, period)` in relational schema). Runs at startup for managers; a tenant session only materialises its own due, never persists owner-wide. ✅
- **Rent history preserved:** `Payment.amount` is fixed at creation; changing a room's rent later never rewrites existing dues/payments. ✅

## Payment workflow (current)
- Owner `recordPayment` settles the matching current-month due in place (full→paid, part→partial) or creates a standalone advance row; no duplicate current-month rows. ✅
- Partial payments supported (`paidAmount`, `collected`, `balance`, `Partial` status). ✅
- **Tenant `payRent` marks the due paid directly.** ❌ Violates "tenant never confirms payment." Manual-UPI submit/confirm flow is **Pending** (Prompt 9).

## Invite workflow (current)
- Owner invites a tenant via `inviteTenant` → `invite` Edge Function: creates the tenant auth user (temp password, `must_change_password`), links via `members`, returns credentials to share (APK + web links). ✅
- Invite **tokens / states (pending/accepted/expired/revoked) are Pending** (Prompt 7). Invited tenants get no `profiles` row.

## Notifications & announcements
- In-app notifications are role-scoped (`visibleNotifications`: tenant sees own + workspace; managers see managerial + active-PG). ✅
- Announcements have an audience (all / specific PG); tenants see only their PG's + global (`visibleAnnouncements`). ✅
- Push (FCM) via `push` function respects notification scope and the `pushEnabled` preference. ✅

## Audit logging
- **Pending** (Prompt 8). `audit_logs` table exists in schema B; no reads/writes in app or functions.

## Disabled customer behaviour
See `04` and `09`: owners blocked, profile-less tenants not blocked.
