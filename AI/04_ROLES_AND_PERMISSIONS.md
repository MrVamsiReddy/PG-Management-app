# 04 · Roles & Permissions

Target model + what the code enforces today. ✅ enforced · ⚠️ partial/UI-only · ❌ violated (see `09`).

## Login resolution
`signInCloud(email, password, portal)` → `_enterCloud` → `_fetchAccessGate` (`profiles` + `customers`) → `evaluateProfileAccess` (`access.dart`):
- Profile with `platform_admin` → admin. Owner/tenant → require enabled customer, else blocked.
- `portalError` requires the resolved role to match the portal used.
- **Legacy pass-through:** if no `profiles` row exists, the gate returns "no authority" and login falls back to membership/metadata resolution (no customer-status check). Most existing accounts and invited tenants take this path. ⚠️

## Platform Admin
Responsibilities: manage customers and platform admins.
- Allowed: create platform admin (via `create-admin` fn + setup key) ✅; create/enable/disable customer (`create-customer` fn, `setCustomerStatus`) ✅; view customers ✅; view a customer's PGs ❌ (`loadCustomerPgNames` reads relational `pgs`, which the app never writes → always empty); view audit logs — Pending.
- Forbidden: PG/rent/payment operations. In `owner_app` admin → `CustomerManagementScreen` only ✅. In `main.dart` (combined) admin → PG `HomeShell` ❌.
- Screens: `CustomerManagementScreen`. Edge Functions: `create-admin`, `create-customer`.

## Customer / Owner
Responsibilities: run own PGs.
- Allowed: PG setup wizard, rooms/beds, onboard tenants, record payments, notices, complaints (maintenance), visitors, CSV export, invite tenants ✅ (on the live `app_data` workspace).
- Forbidden: platform admin, other customers' data. Isolation is by `app_data.owner_id` RLS, **not** `customer_id` ⚠️ (works owner-to-owner; not the customer model).
- Screens: `HomeShell` (Dashboard/Manage/Rent/Requests/Profile), `PgListingsScreen`, `RoomsScreen`, `TenantsScreen`, `PaymentsScreen`, `MaintenanceScreen`, `VisitorsScreen`, `AnnouncementsScreen`, `SettingsScreen`, `PgSetupWizard`.
- APIs/Functions: `invite`, `push`; `app_data` reads/writes.

## Tenant
Responsibilities: view own rent/notices/complaints/visitors; submit payment.
- Allowed: view own rent (`tenantPayments`), raise complaints, add visitors, view notices/announcements (`visibleAnnouncements`), edit own profile/KYC ✅ (scoped in app code).
- Forbidden: business management (no owner screens in tenant build) ✅; confirm payment ❌ — tenant "Pay rent" calls `payRent` which sets status **paid** (`finance_screens.dart` `_paymentFlow` → `app_state.payRent`); audit logs (Pending anyway); other tenants' data ⚠️ (client-side filtering on a shared workspace blob, not RLS).
- Screens (tenant build): `TenantShell` → `TenantHome`, `PaymentsScreen`, `MaintenanceScreen`, `VisitorsScreen`, `TenantProfileScreen`, `NotificationsScreen`, `AnnouncementsScreen`, `SettingsScreen`.
- Tenant build imports no owner/admin screens ✅.

## Disabled customer
- Owner with a `profiles` row → blocked at login/refresh ✅.
- Tenant invited after P7 by an owner with a resolved customer → has a `profiles` row → blocked ✅.
- Tenant without a `profiles` row (legacy invite, or owner without a customer) → **not** blocked ❌ (see `09`).

## Removed from product (data kept internal, no UI)
Utility billing, Attendance, Rental agreement.
