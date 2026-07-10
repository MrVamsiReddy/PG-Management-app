# 03 · Database

Two coexisting models. RLS design → assumptions below; runtime gap → `09_KNOWN_ISSUES.md`.

## A. `app_data` blob store (LIVE at runtime)
Files: `supabase/schema.sql`, `002_members.sql`, `003_push_tokens.sql`, `006_invites.sql`, `007_payments.sql`.

- **`app_data`** — one JSONB row per `(owner_id, key)`; `key` ∈ {pgs, rooms, tenants, payments, maintenance, visitors, announcements, attendance, utilities, notifications}. Whole collections stored as JSON blobs. RLS: owner reads/writes own rows; invited members (via `members`) may read the workspace and write tenant-facing keys. `006` adds restrictive policies: a JWT still carrying `must_change_password=true` cannot write.
- **`members`** — `(owner_id, member_email, tenant_id)`; links an invited tenant email to a workspace + tenant record.
- **`invites`** (P7, live) — `(id, owner_id, customer_id?, user_id?, tenant_id[text], email, pg_id, room_id, bed_label, token[unique], status[pending|accepted|expired|revoked|resent], expires_at, created/accepted/revoked/resent timestamps)`. RLS: owner reads own rows; **all writes are service-role only** (the `invite` Edge Function owns every lifecycle transition, so tokens are single-use and can't be forged).
- **`pg_upi_settings`** (P9, live) — `(owner_id, pg_id[text], upi_id, payee_name, enabled)`; owner writes, workspace members read. PG UPI config for tenant payments.
- **`payment_submissions`** (P9, live) — `(id, owner_id, customer_id?, pg_id, tenant_id[text], member_email, payment_id, period, amount, utr, screenshot_path, status[pending_confirmation|confirmed|rejected], rejection_reason, submitted_at, confirmed_by, confirmed_at)`. RLS: tenant may **insert only** their own `pending_confirmation` row and read own; owner full control of own workspace; platform admin read-only. No tenant UPDATE → a tenant can never confirm/mark paid. `007` also drops `payments` from the members-writable `app_data` keys. Screenshots go to the private `payment-proofs` bucket (`{owner}/{pg}/{tenant}/{payment}/…`, workspace-scoped policies via `can_access_workspace`).
- **`push_tokens`** — `(token, user_id, email)`; FCM device tokens; owner-only RLS.

This is the store the owner/tenant apps actually read and write, **cloud-only** — Supabase is the single source of truth; there is no local store or offline cache (Hive was removed). Collections live in memory only while signed in (`SupabaseRepository`, populated on login, cleared on logout). It is **not** `customer_id`-scoped (scoping is by `owner_id`).

## B. Relational SaaS schema (DEFINED, mostly UNUSED at runtime)
File: `supabase/004_saas_core.sql`. Every business table has `NOT NULL customer_id` (except `customers`, `profiles`, `audit_logs` where `customer_id` is the scope or nullable).

Tables:
- `customers` (id, business_name, owner_name, owner_email, phone, status[enabled|disabled], plan, created_at, disabled_at)
- `profiles` (id=auth.users, customer_id, role[admin|owner|tenant], platform_admin, full_name, phone)
- `pgs`, `floors`, `rooms`, `beds`, `tenants`, `tenant_invites`
- `rent_rules` (per sharing_type, effective_from — rent history), `pg_payment_settings` (UPI)
- `payment_dues` (rent snapshot; unique(tenant_id, period)), `payments`, `payment_submissions` (UTR + status), `payment_proof_files`
- `complaints`, `notices`, `visitors`, `audit_logs`

File: `supabase/005_admin_setup.sql` — `admin_setup_attempts` (rate-limit log; RLS on, no policies = service-role only).

**Used by app today:** `customers`, `profiles`, `pgs` (admin reads), `admin_setup_attempts` (function), and `audit_logs` (P8: app `_audit()` inserts + `loadAuditLogs` reads; edge functions insert via service role). All owner/tenant business data uses store A. `floors`/`beds`/`rent_rules`/`payment_*`/`tenant_invites`/`complaints`/`notices` relational tables are unqueried by the app.

## Relationships (relational schema B)
```
customers 1─* pgs 1─* floors 1─* rooms 1─* beds 1─1 tenants
customers 1─* profiles
pgs 1─* rent_rules,pg_payment_settings,notices,visitors,complaints
tenants 1─* payment_dues 1─* payment_submissions 1─* payment_proof_files
tenants 1─* tenant_invites
customers 1─* audit_logs (customer_id nullable → platform actions)
```

## ER diagram (text)
```
customers
 ├─ profiles (role, platform_admin)
 └─ pgs
     ├─ floors ── rooms ── beds ── tenants ── payment_dues ── payment_submissions ── payment_proof_files
     │                                    └─ tenant_invites
     ├─ rent_rules   ├─ pg_payment_settings
     ├─ notices      ├─ visitors      └─ complaints
audit_logs (customer_id | NULL)
admin_setup_attempts (service-role only)
```

## customer_id usage
- Relational tables: real `NOT NULL customer_id` FKs + RLS scoping (schema B).
- App runtime: `customer_id` is stamped into `app_data` JSON records as metadata (`AppState.customerId`, interim = resolved customer id / workspace owner id / `''`) but is **not** used in any query or policy.

## Foreign keys
Schema B uses `on delete cascade` down the hierarchy; `set null` for optional links (tenant→room/bed, audit actor). Schema A has no FKs (JSON blobs).

## Storage buckets
- `payment-proofs` (private) with policies keyed on path `{customer_id}/{pg_id}/{tenant_id}/{due_id}/…` (defined in `004`, unused by app).

## RLS assumptions (schema B)
- Security-definer helpers (`is_platform_admin`, `my_owner_customer_id`, `my_tenant_ids`, …) all filter on `customers.status='enabled'` → disabled customers fail closed.
- Platform admin: all rows. Owner: own `customer_id`. Tenant: own tenant rows; read own PG/room/beds; **no write policy on `payment_dues`**; may insert only `pending_confirmation` submissions.
- **Caveat:** these guarantees apply to schema B, which the owner/tenant runtime does not use. Live enforcement is schema A's owner/member RLS. See `09`.
