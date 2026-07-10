# 02 · Architecture

Implementation structure only. Roles → `04`; rules → `05`.

## Build surfaces (entry points)
- `lib/main.dart` → `PgManagementApp` — combined app; shows all three login portals; admin lands on the PG `HomeShell`. Used for dev/tests. (Not role-clean; see `09`.)
- `lib/main_owner.dart` → `OwnerAdminApp` — owner + admin portals only; admin → `CustomerManagementScreen`, owner → `HomeShell`, tenant session blocked.
- `lib/main_tenant.dart` → `TenantApp` — tenant login only; `TenantShell`; non-tenant session blocked.
- All three call `lib/src/bootstrap.dart` `bootstrap()` (Supabase init, `AppState()`, `restoreCloudSession`, push registration). No local store to initialise.

## State management
- Single `AppState extends ChangeNotifier` (`lib/src/app_state.dart`), exposed via `AppScope` (an `InheritedNotifier`). `AppScope.of(context)` reads it.
- Holds all business collections in memory as typed model lists and notifies listeners on change.
- `AnimatedBuilder(animation: state)` at the app root rebuilds `MaterialApp` so locale changes apply.

## AppState responsibilities
- Session: `signInCloud(portal)`, `restoreCloudSession`, `logout`, `changePassword`, `createAdmin`, customer methods (`loadCustomers`/`createCustomer`/`setCustomerStatus`/`loadCustomerPgNames`), `debugSignIn` (`@visibleForTesting`).
- Access gate: `_fetchAccessGate` + `access.dart` (`evaluateProfileAccess`, `portalError`).
- Business ops: property/room CRUD (`createProperty`, `addRoom`, `removeRoom`, `setRoomBeds`, `setRoomRent`), `onboardTenant`, rent (`recordPayment`, `payRent`, `generateMonthlyDues`), maintenance, visitors, announcements, notifications.
- Scoping getters: `activePg`, `pgRooms/pgTenants/pgPayments/pgMaintenance/pgVisitors`, `tenantPayments`, `visibleNotifications`, `visibleAnnouncements`.
- Preferences: `language`, `pushEnabled` (session-scoped, in memory; not persisted across launches).

## Repository pattern
- `lib/src/repositories.dart`: `Repository<T>` interface with one impl:
  - `SupabaseRepository<T>` — reads/writes the `app_data` table (one JSONB row per `(owner_id, key)`), **not** the relational tables. Cloud-only; there is no local/offline store.
- `AppState` holds nullable repos, set on cloud sign-in (`_useSupabaseRepos`) and cleared on `logout`. Signed out, collections are empty and persistence no-ops.
- The relational customer-scoped tables (`04` migration) are **not** accessed by these repos. Admin customer management queries `customers`/`pgs`/`profiles` directly via the Supabase client.

## Navigation
- Per-role tab sets built in `HomeShell` (owner/admin) and `TenantShell` (tenant).
- Owner-only screens wrapped in `ManagerOnly` guard.
- Push navigation via `Navigator.push`/`MaterialPageRoute`; no named-route table.

## Supabase integration
- `lib/src/supabase_config.dart`: project URL + publishable key + `appWebUrl`/`apkDownloadUrl`. `supabaseReady`/`supabaseOrNull`.
- Client calls: `.from(table)`, `.functions.invoke(name)`, `.auth`.

## Edge Functions (`supabase/functions/`)
- `create-admin` — server-key-gated platform-admin creation.
- `create-customer` — platform-admin creates customer + owner user.
- `invite` — owner provisions a tenant login (legacy `members`/`app_data` model).
- `push` — FCM fan-out to a workspace, scope-aware.

## Storage
- `payment-proofs` bucket + path-scoped policies defined in `004` (schema only; not yet used by any screen).

## Folder structure
```
lib/
  main.dart / main_owner.dart / main_tenant.dart
  src/
    app_state.dart access.dart bootstrap.dart repositories.dart supabase_config.dart push.dart
    models.dart saas_models.dart l10n.dart theme.dart format.dart widgets.dart receipt_pdf.dart
    auth_screen.dart home_shell.dart dashboard_screen.dart module_screens.dart
    property_screens.dart finance_screens.dart operations_screens.dart community_screens.dart
    settings_screen.dart admin_customers.dart pg_wizard.dart owner_app.dart tenant_app.dart
supabase/
  schema.sql 002_members.sql 003_push_tokens.sql 004_saas_core.sql 005_admin_setup.sql
  functions/{create-admin,create-customer,invite,push}/index.ts
test/app_test.dart
AI/  (this kit)
```

## Dependency flow
UI screens → `AppScope.of` → `AppState` → `Repository` (`app_data`) and/or Supabase client/functions. Pure logic (`access.dart`, `format.dart`) has no Flutter/Supabase deps and is unit-tested directly.
