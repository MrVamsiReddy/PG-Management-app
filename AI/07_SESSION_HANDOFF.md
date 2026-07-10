# 07 · Session Handoff

Reusable template. Copy the block per work session; keep the most recent at top. Don't duplicate `06`/`09` — reference them.

## Template
```
### Session: <YYYY-MM-DD> · <short title>
Prompt/goal:
Commit(s):

Summary:
- <what changed in one or two lines>

Files modified:
- lib/src/... (why)
- supabase/... (why)

Architecture changes:
- <new files/classes, dependency-flow changes, or "none">

Database changes:
- <migrations added/edited, tables, RLS, or "none">

Tests added:
- <test names> · total count · analyze status

Remaining work:
- <what's deferred; link 06 pending items>

Known issues introduced/affected:
- <link 09 items>

Next task:
- <the single next action>
```

## Latest
```
### Session: 2026-07-10 · Prompt 7 — tenant invite tokens & temporary passwords
Prompt/goal: Owner-only tenant onboarding via Edge Function with one-time tokens, temp passwords, full lifecycle (pending/accepted/expired/revoked/resent) and backend must_change_password enforcement.
Commit(s): (this session)

Summary:
- Rewrote the `invite` Edge Function with actions create/resend/revoke/validate/accept: creates the tenant auth user (temp password, role/customer_id/pg_id/room_id/bed_id/tenant_id metadata, must_change_password=true), a profiles row (when the owner has a resolved customer), the members link, and an `invites` row with a single-use token + 7-day expiry. Revoke scrambles a never-used temp password; resend supersedes (status resent) and regenerates the password only while onboarding is incomplete. Expired/revoked invites block the tenant's first sign-in; password change refreshes the JWT and consumes (accepts) the invite. Removed the client-side members-upsert fallback — invites now require the function.

Files modified:
- supabase/006_invites.sql (new: invites table, service-role-write-only RLS, resent state on tenant_invites, restrictive app_data write policies while must_change_password)
- supabase/functions/invite/index.ts (rewritten; never logs passwords; code:* errors)
- lib/src/app_state.dart (InviteResult; inviteTenant/resendInvite/revokeInvite/_inviteAction; _inviteLoginError gate in _enterCloud; changePassword refreshes session + accepts invite)
- lib/src/invite_message.dart (new: buildInviteMessage — email, temp password, APK/web/invite links, instructions, expiry)
- lib/src/saas_models.dart (InviteStatus.resent; inviteAcceptError mirror of server validation)
- lib/src/access.dart (inviteActionMessage code→text)
- lib/src/property_screens.dart (share via builder; resend/revoke menu per tenant)
- test/app_test.dart (8 new tests)
- AI/03,04,05,06,09,11 (reflect P7)
- Repo-wide dart format applied (large cosmetic diff in app_state/property_screens).

Architecture changes:
- New pure module invite_message.dart; invite lifecycle owned entirely server-side (clients cannot write invites).

Database changes:
- 006_invites.sql (see above). Run once; then redeploy the `invite` function.

Tests added:
- invite message contents (credentials + existing-account variants), single-use/expiry/revocation matrix, resent round-trip, error-code mapping, offline resend/revoke, 006 migration lockdown, invite fn lifecycle/no-logging. 83 passing; analyze clean.

Remaining work:
- P8–P11 (see 06). Legacy tenants still lack profiles rows (09 P1, narrowed).

Known issues introduced/affected:
- 09: must_change_password write enforcement resolved; disabled-customer tenant gap narrowed to legacy invites.

Next task:
- Prompt 8 (audit logs) or the runtime→relational migration (06 "Next recommended phase").
```

```
### Session: 2026-07-10 · Cloud-only data layer (remove Hive/demo/seed)
Prompt/goal: Make Supabase the single source of truth — remove the local store, demo mode and mock seed path.
Commit(s): (this session)

Summary:
- Deleted the Hive local store, HiveRepository, the _seed() demo data, debugSeedDemoData, and the cloudMode/'demo'/defaultTenantId/ownerName fallbacks. app_data (cloud) is now the only store; repos are nullable and set on login, cleared on logout. Preferences are session-scoped.

Files modified:
- lib/src/repositories.dart (drop HiveRepository; SupabaseRepository only)
- lib/src/app_state.dart (remove box/init/seed/schemaVersion/_useHiveRepos; nullable repos; login→debugSignIn; logout clears state; best-effort _persist)
- lib/src/bootstrap.dart, lib/main.dart (no Hive; main.dart reuses bootstrap)
- lib/src/property_screens.dart, lib/src/settings_screen.dart (cloudMode→isLoggedIn)
- lib/src/models.dart (doc comment)
- pubspec.yaml (remove hive_flutter)
- test/app_test.dart (in-memory seedFixture + debugSignIn; drop Hive/persistence tests)
- AI/01,02,03,06,08,09,10 (reflect cloud-only reality)

Architecture changes:
- No local/offline store. AppState repos nullable; populated in _useSupabaseRepos on sign-in, nulled on logout. cloudMode removed (== isLoggedIn).

Database changes: none (still writes app_data blob keyed by owner_id).

Tests added: none new; suite reshaped to cloud-only. 75 passing; analyze clean.

Remaining work: migrate runtime to relational customer_id tables (06 "Next recommended phase"); Prompts 7–11.

Known issues introduced/affected: 09 P0 (still app_data, not relational RLS) narrowed — Hive/seed debt items removed; new P3: signed-out prefs don't persist.

Next task: Prompt 7 (tenant invite tokens + profiles row) or the relational-runtime migration.
```

```
### Session: 2026-07 · AI documentation kit
Prompt/goal: Generate permanent AI/ docs from current implementation.
Commit(s): (docs only)

Summary:
- Added AI/ folder (12 docs) reflecting Prompts 1–6 done, 7–11 pending.

Files modified:
- AI/*.md (new)

Architecture changes: none.
Database changes: none.
Tests added: none (77 existing pass; analyze clean).

Remaining work: Prompts 7–11 (see 06). Priority: migrate runtime to relational tables (see 06 "Next recommended phase").

Known issues: see 09 (P0 runtime store; tenant marks paid).

Next task: Prompt 7 (tenant invite tokens) OR the runtime→relational migration.
```

## Prior sessions (condensed)
- P6 (`65f25c6`) PG onboarding wizard + structure guards.
- P5 (`4f18941`) customer management + `create-customer`.
- P4 (`6c84386`) admin setup key + `create-admin`.
- P3 (`3413dbc`) owner/tenant app split.
- P2 (`6d8f2de`) strict login; demo mode removed.
- P1 (`a301c0e`) SaaS data model + `004` schema/RLS. Migration ordering fix `1d77197`.
