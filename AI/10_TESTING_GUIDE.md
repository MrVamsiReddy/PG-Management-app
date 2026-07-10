# 10 · Testing Guide

## Run
```bash
flutter analyze          # must be clean (infos count)
flutter test             # test/app_test.dart — 75 passing
```
> Do **not** run `dart format lib` — the codebase is intentionally dense (no formatter config / wide lines). A default 80-col `dart format` reflows every file and turns one-line `if`s into a `curly_braces_in_flow_control_structures` lint. Keep new code hand-dense to match.

## Strategy
Single suite `test/app_test.dart`. Three kinds:
1. **Pure unit** — logic with no Flutter/Supabase deps (`access.dart`, `format.dart`, `AppState` methods on the in-memory model).
2. **Widget** — screens/apps pumped with `AppScope` + `MaterialApp` (+ localization delegates where needed).
3. **Artifact audits** — read `supabase/*.sql` and `functions/*/index.ts` as text and assert security-relevant invariants (RLS enabled, key from secret, no seed inserts, etc.), because Deno/Postgres can't run in `flutter test`.

## Harness conventions (important)
- The app is cloud-only — there is no local store or seed path. `setUp` builds a bare `AppState()` and calls the test-file `seedFixture(state)` helper, which writes demo data straight into the public collections (`state.pgs = [...]`, etc.). Production never seeds.
- Use `state.debugSignIn(UserRole.x, {tenantId})` (`@visibleForTesting`) to simulate a session — there is no real Supabase in tests, so `signInCloud`/customer/admin calls fail closed (assert the error path). Tenant tests pass `tenantId: 't1'` (or set `state.currentTenantId` directly for a non-session unit test).
- Widget tests use **bounded pumps** (`pump()` + `pump(Duration)`), not `pumpAndSettle`, because pending fire-and-forget cloud IO never settles in the fake-async zone. Exception: pushing a route with no pending IO can use `pumpAndSettle`.
- `StatCard` text sits inside a `FittedBox`; tap the enclosing `InkWell` (`find.ancestor(... find.byType(InkWell))`), not the text.

## What is covered
- Access resolution + portal matrix; disabled owner/tenant (via `evaluateProfileAccess`); offline creates no session.
- Payment logic: record settles-in-place, partial, advance; monthly dues idempotency; rent snapshot preserved.
- Onboarding validation; structure-reduction guards.
- Tenant privacy (notifications/payments); announcement audience filtering.
- App separation: tenant surface has no owner routes; owner/admin auth has no tenant portal/sign-up; admin sees customer management.
- Function/migration audits: `create-admin`, `create-customer`, `004`/`005`.
- Localization: language persists; nav localizes; profile/announcement interactions.

## Security / RLS tests
- **RLS is audited by text only** today (asserting policies exist and dues have no tenant write path). True cross-customer/cross-tenant RLS proof needs two live Supabase users; steps are documented at the bottom of `004_saas_core.sql`. Not automated.
- Edge Function runtime paths (rate-limit, expiry, timing-safe) are **not** executed by the suite — covered by text audit + the pure client error-code mapping.

## Coverage expectations
- Every new pure logic method: a unit test.
- Every new screen surface / role gate: a widget test asserting presence/absence.
- Every new migration/function: a text-audit test of its security invariants.
- Keep `flutter analyze` clean (treat infos as failures — codebase policy).

## Gaps (see 09)
No automated RLS, Edge Function runtime, or integration (device/emulator) tests.
