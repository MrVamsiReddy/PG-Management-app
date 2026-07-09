# 12 · Prompt Template

Reusable prompt for future implementation sessions. Keeps context small.

## Use this prompt
```
Read AI/01_PROJECT_CONTEXT.md, AI/06_PROJECT_STATUS.md, and the latest
entry in AI/07_SESSION_HANDOFF.md. Inspect the repository only where the
task needs it (don't re-audit everything).

Constraints:
- Base all work on the current source. Don't invent features.
- Follow the non-negotiable rules in 01 and the decisions in 08.
- Write minimal code. No comments in code.
- Don't reintroduce demo mode, public sign-up, or owner screens into the
  tenant surface. Don't let a tenant confirm payment.

Task: <describe the task, e.g. "Implement Prompt 7: tenant invite tokens">

When done:
1. Run: dart format (touched files), flutter analyze, flutter test — all green.
2. Add/adjust tests (see AI/10_TESTING_GUIDE.md conventions).
3. Update AI/06_PROJECT_STATUS.md and prepend an AI/07_SESSION_HANDOFF.md entry.
4. If you added a migration/function/secret, update AI/11_DEPLOYMENT_GUIDE.md.
5. Commit + push. Give a short summary: what changed, files, tests, risks.
```

## Guardrails for the assistant
- Prefer the relational customer-scoped tables (`03`/schema B) for new backend work; call out when you must touch the legacy `app_data` runtime (`09` P0).
- New Edge Functions: return stable `code:*` errors; never return/log secrets; verify the caller's role server-side.
- New user-facing strings: add keys to `l10n.dart` (en/hi/te) rather than hardcoding.
- Keep `flutter analyze` treating infos as failures.
- Update the relevant AI doc instead of duplicating content across files.
