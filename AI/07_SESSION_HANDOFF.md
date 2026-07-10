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
### Session: 2026-07-10 · Improvements #6 — subscription management
Prompt/goal: Customer creation stores plan + starts_at + expires_at (free/30d default; admin picks plan); auto-disable + block login on expiry with a message.
Commit(s): (this session)

Summary:
- 009_subscriptions.sql: add starts_at (default now) + expires_at to customers, backfill = created_at+30d, and redefine my_owner_customer_id() to also require c.expires_at > now().
- create-customer: sets starts_at=now, expires_at=now+durationDays (default 30), plus admin-selected plan.
- Customer model: startsAt/expiresAt fields + expired/active getters; _customerFromRow parses starts_at/expires_at; loadCustomers select() already returns them; _fetchAccessGate now selects status,expires_at.
- Login gate (access.dart evaluateProfileAccess): blocks owner+tenant with "subscription has expired" when expires_at < now.
- admin_customers UI: create dialog has a plan dropdown (free/pro/business); card shows plan + renews/expired date + Expired pill.

Files modified:
- supabase/009_subscriptions.sql (new), supabase/functions/create-customer/index.ts
- lib/src/saas_models.dart, lib/src/app_state.dart (row parse + gate select), lib/src/access.dart, lib/src/admin_customers.dart
- test/app_test.dart (expiry gate, model expired/active, migration/function content)
- AI/05,06,07,11 updated

Deploy: run 009_subscriptions.sql; redeploy create-customer. Enforcement is at login (no cron) — expired customers are blocked on next login/refresh.

Tests: 113 passing; analyze clean; dart format applied.

Next task: #7 dashboard improvements (spacing/typography/hierarchy + favorite tiles with gold star, favorites first, persisted per user).
```

```
### Session: 2026-07-10 · Improvements #5 — password management
Prompt/goal: Reset links work; first login requires temp+new+confirm; enforce must_change_password front+back; gate access until password set.
Commit(s): (this session)

Summary:
- SetPasswordScreen: added a Temporary password field (first-login only, hidden during recovery) + New + Confirm. changePassword(newPassword, {currentPassword}) re-validates the temp password via signInWithPassword before updateUser; returns code:bad_credentials on mismatch.
- Reset links: sendPasswordReset now passes redirectTo: appWebUrl. bootstrap onAuthStateChange handles AuthChangeEvent.passwordRecovery → state.markPasswordRecovery(). New passwordRecovery flag + needsPasswordSet getter (= mustChangePassword || passwordRecovery); all three entry points (owner_app/main/tenant_app) gate on needsPasswordSet. changePassword clears both flags; logout resets passwordRecovery.
- must_change_password still enforced client + server (006 restrictive app_data policies, unchanged).
- l10n: setpw.temp + setpw.tempReq (en/hi/te).

Files modified:
- lib/src/app_state.dart (passwordRecovery/needsPasswordSet/markPasswordRecovery, changePassword currentPassword, sendPasswordReset redirectTo, logout reset)
- lib/src/bootstrap.dart (recovery event), lib/src/auth_screen.dart (temp field), owner_app/tenant_app/main.dart (gate), lib/src/l10n.dart (2 keys ×3)
- test/app_test.dart (needsPasswordSet/recovery/logout, changePassword fail-closed, 2 widget tests)
- AI/05,06,07 updated

Manual: Supabase Auth → set Site URL / redirect allow-list to appWebUrl so reset links land back in the app.

Tests: 110 passing; analyze clean; dart format applied. No new migration/function.

Next task: #6 subscription management (plan + starts_at/expires_at; 30-day free default; admin picks plan; auto-disable on expiry + block login with message).
```

```
### Session: 2026-07-10 · Improvements #4 — room pricing model (verify + tighten)
Prompt/goal: Room=sharing+rent, Tenant=bed+room, Payment=snapshot; rent changes affect future only, preserve history.
Commit(s): (this session)

Summary:
- Verified the model was already implemented: Payment.amount is the rent snapshot (set by idempotent generateMonthlyDues from roomById(tenant.roomId).rent); setRoomRent mutates only the room; existing dues never rewritten; future dues/new tenants pick up the new rent.
- Added Room.sharingType getter (= beds) for explicit modeling.
- Fixed a latent uniqueness bug: _id() now appends a monotonic counter (microsecond clock is coarse on Windows, so two rapid onboardings could mint the same tenant id → colliding payment id → skipped due). This surfaced via the new future-dues test.

Files modified:
- lib/src/models.dart (Room.sharingType), lib/src/app_state.dart (_id counter)
- test/app_test.dart (pricing-model + future-only-rent tests)
- AI/06,07 updated

Tests: 106 passing; analyze clean; dart format applied. No backend/deploy changes.

Next task: #5 password management (reset links work; first-login temp+new+confirm; must_change_password enforced front+back). Note 006 already enforces must_change_password server-side; verify + add confirm-password on set-password if missing.
```

```
### Session: 2026-07-10 · Improvements #3 — tenant onboarding sets room pricing
Prompt/goal: Onboarding collects PG/Floor/Room/Bed/Sharing Type/Current Rent; sharing+rent belong to the room; tenant inherits them.
Commit(s): (this session)

Summary:
- TenantsScreen._onboard rewritten: PG dropdown, Room dropdown (existing rooms + "＋ New room"); for a new room it reveals Room number, Floor, Sharing type (1–4), Current rent; existing rooms show inherited sharing/rent. Bed + name/phone/KYC as before.
- AppState.ensureRoom(pgId, floor, roomNumber, sharingType, rent) → creates the room if absent (beds=sharingType, rent), idempotent per (pg, room number), bumps PG bed count, audits room_created; returns the room id. Onboarding calls it for new rooms, then onboardTenant(roomId,...). Tenant's first due is generated at the room's rent (snapshot).
- Room.type extended to 4 (Four sharing).

Files modified:
- lib/src/app_state.dart (ensureRoom), lib/src/property_screens.dart (onboarding UI), lib/src/models.dart (Room.type)
- test/app_test.dart (new-room onboarding + inherit-rent + idempotent ensureRoom)
- AI/05,06,07 updated

Tests: 104 passing; analyze clean; dart format applied. No backend/deploy changes.

Next task: #4 room pricing model (Room=sharing+rent, Tenant=bed+room, Payment=snapshot; rent changes affect future only) — mostly already true; verify + tighten.
```

```
### Session: 2026-07-10 · Improvements #2 — PG creation simplified
Prompt/goal: PG creation collects only name/address/basic info; remove sharing type + rent config from PG creation.
Commit(s): (this session)

Summary:
- pg_wizard.dart rewritten from a 4-step Stepper (details/rent-by-sharing/floors-rooms-beds/review) to a single form: PG name, address, amenities → Create. No rent, no sharing, no room generation.
- createProperty(name, address, amenities, [specs]) — specs now optional (default const []); removed the "add at least one room" guard so a PG can start with zero rooms (rent/sharing set later per tasks 3/9).
- l10n: added wiz.created + wiz.basicInfo (en/hi/te). Old wiz.* keys retained (reused by onboarding/rooms later).

Files modified:
- lib/src/pg_wizard.dart (simplified), lib/src/app_state.dart (createProperty optional specs)
- lib/src/l10n.dart (2 keys ×3), test/app_test.dart (wizard widget test updated; new no-rooms test)
- AI/05,06,07 updated

Tests: 103 passing; analyze clean; dart format applied. No backend changes (no deploy needed).

Next task: #3 tenant onboarding (select PG/floor/room/bed/sharing/rent; tenant inherits room values).
```

```
### Session: 2026-07-10 · Improvements #1 — customer deletion
Prompt/goal: Platform admin can permanently delete a customer + cascade all data (no orphans), transactional server-side, admin-only.
Commit(s): (this session)

Summary:
- 008_delete_customer.sql: admin_delete_customer(target) SECURITY DEFINER plpgsql (single transaction) purges app_data/members/invites/pg_upi_settings/upi_submissions/push_tokens/audit_logs/profiles by owner/customer, then deletes the customers row (cascades all 004 relational tables); returns user ids; execute revoked from public/authenticated.
- delete-customer Edge Function (platform-admin verified): calls the RPC, recursively purges the payment-proofs Storage folder per user id, deletes every auth user (owner + tenants).
- AppState.deleteCustomer → invokes the function, maps code:* errors.
- admin_customers.dart: red delete icon per customer card + confirm dialog; removes row on success.

Files modified:
- supabase/008_delete_customer.sql (new), supabase/functions/delete-customer/index.ts (new)
- lib/src/app_state.dart (deleteCustomer), lib/src/admin_customers.dart (delete UI)
- test/app_test.dart (fail-closed + migration/function content)
- AI/06,07 updated

Deploy: run 008_delete_customer.sql once; deploy the `delete-customer` Edge Function.

Tests: 102 passing; analyze clean; dart format applied.

Remaining: improvements tasks 2–9, executed one at a time on request.

Next task: #2 PG creation simplification (drop sharing/rent from PG create).
```

```
### Session: 2026-07-10 · Prompt 11 — production readiness QA
Prompt/goal: Verify the production checklist against source, fix gaps, run format/analyze/test + owner & tenant web release builds, report remaining blockers.
Commit(s): (this session)

Summary:
- Verified every checklist item by code search: no demo/local/offline/seed code, no public signup, split owner/tenant apps with tenant build excluding owner screen files, RLS on all tables, server-side timing-safe admin key, must_change_password enforced (client + 006 RLS), full invite lifecycle, audit logging incl. payment events, rent history preserved, occupied-structure guards, tenant-cannot-mark-paid, UPI-return-never-auto-confirms, workspace-scoped proof storage, duplicate UTR detection. Fixed the one production-polish issue found: receipt PDF footer said "demo receipt" → "not a valid tax document". dart format clean, analyze clean, 101 tests pass, both `flutter build web --release` (owner + tenant) succeed.

Files modified:
- lib/src/receipt_pdf.dart (footer wording)
- AI/06,07,11 updated (P11 checklist + blockers)

Architecture changes: none.
Database changes: none.
Tests added: none (verification pass); 101 passing.

Remaining production BLOCKERS (unchanged, see 09):
- P0 · runtime still on app_data keyed by owner_id, not relational customer_id RLS (isolation works owner-to-owner, not the customer model).
- P1 · legacy tenants (no profiles row) bypass the disabled-customer gate.
Non-blocking: a few secondary ops/community screens not yet localized; admin "view customer PGs" reads unused relational pgs (empty).

Next task: P0 relational-runtime migration (move app_data reads/writes onto 004 customer-scoped tables) — the last gate to true multi-tenant production.
```

```
### Session: 2026-07-10 · Prompt 10 — full localization
Prompt/goal: Localize the core/tested flows in en/hi/te, persist language, map backend error codes to localized text.
Commit(s): (this session)

Summary:
- Added shared_preferences; language persists (AppState.loadLanguage at bootstrap, setLanguage writes). Expanded l10n _strings with ~90 keys × 3 languages (auth, setpw, adminSetup, dash, qa, wiz, inv, err, status). Localized auth_screen, dashboard_screen, pg_wizard, and the tenant invite dialog in property_screens. signInCloud now returns code:network|bad_credentials|generic; AppLocalizations.error(code) maps backend/auth codes (and passes through human strings).

Files modified:
- pubspec.yaml (+shared_preferences)
- lib/src/app_state.dart (loadLanguage/setLanguage persist; signInCloud → codes; dropped unused PostgrestException show)
- lib/src/bootstrap.dart (await loadLanguage)
- lib/src/l10n.dart (big key expansion en/hi/te + error(code) mapper)
- lib/src/auth_screen.dart, dashboard_screen.dart, pg_wizard.dart, property_screens.dart (use l.t / l.error)
- test/app_test.dart (persistence, error-code map, key-parity, auth/dashboard/wizard/invite widget tests)
- AI/01,05,06 updated

Architecture changes: AppLocalizations.error(code) is the single code→string mapper. Language is the only on-device persisted preference.

Database changes: none.

Tests added: 8 (persistence read/write, error mapping, hi/te key parity, 4 localized-screen widget tests). 101 passing; analyze clean.

Remaining work: P11 (release QA). Localization coverage: some secondary ops/community/room-detail screens still English.

Known issues introduced/affected: none new.

Next task: Prompt 11 (production safety QA + release builds).
```

```
### Session: 2026-07-10 · Prompt 9 — manual UPI rent payments
Prompt/goal: UPI config per PG, tenant submit-proof flow (never auto-confirm / never mark paid), owner confirm/reject, RLS + storage + audit + localization.
Commit(s): (this session)

Summary:
- 007_payments.sql: pg_upi_settings + payment_submissions (tenant may INSERT only a pending_confirmation row, read own; owner full; admin read; NO tenant UPDATE) + revokes tenant 'payments' app_data write + payment-proofs storage policies (can_access_workspace). Removed payRent. New runtime models UpiSettings/UpiSubmission. AppState: loadSubmissions, submitPayment (uploads screenshot, inserts pending, audit payment_submitted, dup handled owner-side), confirmSubmission (→ marks due paid + audit payment_confirmed), rejectSubmission (mandatory reason + audit payment_rejected), loadUpiSettings/saveUpiSettings, paymentStatusKey/canSubmit/duplicateOf/pendingSubmissions/proofUrl. UI upi_screens.dart: tenant showUpiPayFlow (upi:// external + UTR/screenshot submit), owner PaymentReviewScreen (confirm/reject/dup warning/proof), UpiSettingsScreen. Localized en/hi/te (upi.* / status.*).

Files modified:
- supabase/007_payments.sql (new)
- lib/src/models.dart (UpiSettings, UpiStatus, UpiSubmission)
- lib/src/app_state.dart (payment methods, remove payRent, submissions state)
- lib/src/finance_screens.dart (tenant UPI FAB, owner appbar review/settings, derived status pill; removed _paymentFlow/_success)
- lib/src/upi_screens.dart (new: pay flow, review, settings)
- lib/src/l10n.dart (upi.*/status.* in 3 languages)
- test/app_test.dart (P9 tests; replaced 2 payRent tests)
- AI/01,03,04,05,06,09,11 updated

Architecture changes: security-critical payment lifecycle on a dedicated RLS-enforced table (payment_submissions) keyed by owner_id/member_email — genuine enforcement even though dues still live in app_data. Screenshots in payment-proofs Storage.

Database changes: 007 (see above). Run once; not idempotent.

Tests added: status derivation/resubmit, tenant-can't-mark-paid, confirm/reject fail-closed, duplicate UTR warning, UpiSettings/UpiSubmission mappers, 007 RLS content. 93 passing; analyze clean.

Remaining work: P10 (full localization sweep), P11 (release QA). Dues themselves still in app_data (P0 relational migration unchanged). Home/receipt cards still show base displayStatus (due/paid), not the pending overlay — minor.

Known issues introduced/affected: 09 P0 "tenant marks paid" resolved; rule 6 now enforced.

Next task: Prompt 10 (full-app localization).
```

```
### Session: 2026-07-10 · Prompt 8 — audit logs
Prompt/goal: Create and fully integrate audit_logs with role isolation (admin all, owner own, tenant none).
Commit(s): (this session)

Summary:
- audit_logs table + RLS already in 004 (all required fields incl ip/user_agent). Wired writes: edge functions (create-admin→admin_created; create-customer→customer_created+owner_created; invite→tenant_invited/resent/revoked) via service role; app-side AppState._audit() best-effort inserts on customer enable/disable, pg/room create, room removed/beds-changed, rent changed, tenant assigned, payment recorded. Added AuditLogScreen viewer (admin appbar → all logs; owner Settings → own). No schema migration needed.

Files modified:
- lib/src/app_state.dart (_audit helper, loadAuditLogs, call sites; setCustomerStatus logs)
- lib/src/saas_models.dart (AuditLog.fromRow for snake_case db rows)
- lib/src/audit_log_screen.dart (new viewer)
- lib/src/admin_customers.dart (appbar audit-log button), lib/src/settings_screen.dart (owner Activity log tile)
- supabase/functions/{invite,create-customer,create-admin}/index.ts (audit inserts + ip/user_agent)
- test/app_test.dart (4 new tests)
- AI/03,04,05,06,09 updated

Architecture changes: new AuditLogScreen; _audit is fire-and-forget (not awaited), swallows errors.

Database changes: none (audit_logs already in 004). RLS unchanged (admin all, owner own read+append, tenant none).

Tests added: audit_logs RLS isolation, AuditLog.fromRow, loadAuditLogs fails closed, edge-fn audit writes. 87 passing; analyze clean.

Remaining work: P9–P11. payment_submitted/confirmed/rejected logs land with P9. Owner-side app logs only persist for owners with a resolved customer_id (RLS); legacy owners write nothing.

Known issues introduced/affected: none new. 09 P8 item removed.

Next task: Prompt 9 (manual UPI submit/confirm/reject; also make payRent a submission).
```

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
