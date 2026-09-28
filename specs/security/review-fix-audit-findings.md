# Security Review — fix/security-audit (post-fix verification)

Scope: 19 files on branch `fix/security-audit` vs `main` (8344a90).
Fixes audit findings M1–M5, L1–L2 from the 2026-09-28 audit.
Implemented via 4 parallel `worker` lanes with git-worktree isolation, merged clean (no conflicts).

Verdict: **all findings closed. No HIGH/MEDIUM/LOW residual. Merge not blocked.**

## Fix verification

### M1 — Persistent view-DoS via forged `selected` — CLOSED
- `app/models/attempt.rb`: `selected_indices_valid` rejects non-`\d+` and indexes outside `0...options.size`.
- `app/views/questions/_attempt_body.html.erb`: nil-option guard for legacy forged rows.
- Test: forged `selected: ["999"]` creates nothing; question page still 200 (`attempts_controller_test.rb`).

### M2 — Sidecar `/v1/judge` fail-open — CLOSED
- `sidecar/server.py`: exception path now HTTP 500 (was 200 pass+review); Rails `ModerationClient` treats non-200 as transport failure → `:try_later` → fail-closed.
- Test: `sidecar/test_server_security.py` — malformed→500, oversize fails closed in 0.00s, MAT-head rejects.

### M3 — OAuth email/password takeover via session alone — CLOSED
- `app/controllers/profiles_controller.rb`: removed `provider` bypass in `reauthenticated?`; uniform `current_password` check. OAuth users without a known password use the password-reset flow first (intended, documented).
- Tests: 3 new — OAuth email change without password → 422, with password → redirect, hijacked session email+password swap → 422 with credentials unchanged.

### M4 — Production TLS/host hardening — CLOSED
- `config/environments/production.rb`: `force_ssl = true` (+ `/up` redirect exclude), `config.hosts` pinned from `APP_HOST` when set, `host_authorization` `/up` exclude, mailer host from `APP_HOST` (fallback `example.com`). No hand-rolled `secure:` flag — secure cookies come from `force_ssl` (per Rails Guides, Context7 `/websites/guides_rubyonrails`).
- `.env.example`: `APP_HOST` documented. Prod boot smoke-checked with and without `APP_HOST`.

### M5 — Unthrottled signup/email bombing — CLOSED
- `app/controllers/registrations_controller.rb`: `rate_limit to: 10, within: 3.minutes, only: :create`.

### L1 — Unbounded inputs / sidecar load — CLOSED
- Model caps: Comment body 2000; Question title 200, body/reference/explanation 20000; Attempt body 8000 (matches `AttemptJuryJob::MAX_BODY_CHARS`).
- Sidecar: judge body capped at 262144 (same as grade), candidate truncated to 20000 chars before MAT regex + model.

### L2 — Trustee over-privilege + enumeration — CLOSED
- `app/models/question.rb`: new `editable_by?` (author/admin only); `managed_by?` delegates to it. Trustee keeps `privileged?` view/approve/verdict rights.
- `questions_controller.rb` edit/update/destroy gated on `editable?`; `show.html.erb` buttons use `@can_edit`.
- `sync_trustees_by_emails` returns counts only (`Добавлено наблюдателей: X из Y.`) — no per-email oracle.
- Tests updated: trustee edit/update/destroy → 403, no buttons rendered, count message asserted.

## Gates (all green)
- `bin/rails test`: 223 runs, 892 assertions, 0 failures (baseline pre-fix: 212/858/0).
- `bin/brakeman --quiet --no-pager`: no warnings.
- `bin/bundler-audit check`: no vulnerabilities.
- `sidecar/test_server_security.py`: OK.

## Residual notes (below bar, not findings)
- `force_ssl` is unconditional in production; direct-HTTP deploys behind a non-TLS proxy must terminate TLS at Thruster/proxy or set `assume_ssl` accordingly.
- OAuth users must complete one password-reset to learn a password before credential changes — one-time UX cost, accepted.
- `HomeController` LIKE wildcard escaping (`sanitize_sql_like`) still open from tech-stack notes — parameterized (no SQLi), cosmetic matching only.
