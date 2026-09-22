# Security Review — feat/trustee (`ff2e146` vs `origin/main`)

Scope: 16 files, Rails 8 app. User input → sink traces: `trustee_emails` param →
`Question#sync_trustees_by_emails`; `question_id`/`id` params → scoped finds +
`privileged?`/`managed_by?` gates; new outputs (names, titles, tags, emails) via
escaped `<%= %>` / tag helpers. Brakeman + audit clean (pre-existing gates).

Verdict: **no HIGH/MEDIUM findings. 2 LOW.** Merge not blocked.

## Finding 1 — `app/models/question.rb:58` — LOW — User enumeration (CWE-200)

- Description: `sync_trustees_by_emails` returns per-email
  `Пользователь не найден: <email>`, surfaced as flash alert to the author.
  Any registered user can author a question, so any authenticated user gets an
  oracle for "is this email registered?".
- Exploit scenario: attacker authors a draft question, submits guessed emails
  in `trustee_emails`, reads which ones are confirmed missing vs granted/failed
  differently. No rate limit on questions#create/update beyond auth.
- Recommendation: acceptable if deliberate (UX needs to name failures). To
  harden, collapse to a count — `Наблюдателей добавлено: 2, не найдено: 1` —
  without naming the missing address. Confidence: 9/10.

## Finding 2 — `app/models/question.rb:44`, `questions_controller.rb:49` — LOW — Trustee can edit/destroy author's question (CWE-863)

- Description: `privileged?` (author/trustee/admin) gates `edit/update/destroy`
  and `comments#approve`. A granted trustee can therefore edit and even delete
  another user's question (plus dependent attempts/comments). Matches the
  documented "доступ уровня Автора", but destroy exceeds what observation needs.
- Exploit scenario: malicious or compromised trustee deletes the author's
  question pre-deadline, destroying all respondents' attempts. Requires being
  granted first (trusted party), so likelihood is low.
- Recommendation: if observation-only is the intent, split the gate —
  `privileged?` for view/approve, author-or-admin for `edit/update/destroy`.
  If author-equivalence is deliberate, record it in `.scratch/trustee/spec.md`
  and close this finding. Confidence: 8/10.

## Checked and cleared

- SQLi (CWE-89): `User.where(email: [...])`, `where.not(user_id: ...)`,
  `trustees.exists?(user.id)` — all bound parameters, no interpolation. Safe.
- XSS (CWE-79): trustee names/titles/tags/emails render via escaped helpers;
  reflected `params.dig(:question, :trustee_emails)` goes through
  `text_field_tag` (escaped). Safe.
- IDOR/scope (CWE-639): `my_questions` lists derive from `Current.user` only;
  `Question.find` results pass `privileged?`/`managed_by?` before any
  privileged read or write; sync ignores `trustee_emails` from non-managers
  (tested). Safe.
- Mass assignment: `trustee_emails` handled outside `question_params`. Safe.
- CSRF: standard `form_with` tokens; no `skip_forgery_protection`. Safe.
- Secrets: none added; migration/schema contain no sensitive data. Safe.
- Email matching: `User normalizes :email (strip.downcase)` matches sync's
  downcase/strip — no case-variant bypass or phantom-missing. Safe.

## Below-bar note (not a finding)

- `trustee_emails` list length is unbounded: a huge comma list builds one large
  `IN` query + N writes, author-only and authenticated. Cap at ~20 with a
  message if abuse ever shows up; no action now.
