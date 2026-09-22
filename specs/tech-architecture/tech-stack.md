# Project Context — QuizForum (derived 2026-09-22, cold read)

> Note: skill mandates `specs/`; repo SoT is `.scratch/` (AGENTS.md). This file is the only `specs/` artifact so far.

## Stack

- Ruby 4.0.7, Rails 8.1.3.1 (edge), PostgreSQL (`pg`), Puma + Thruster, Kamal/Docker deploy
- Hotwire via Importmap: `turbo-rails` used; `stimulus-rails` in Gemfile but zero controllers, `application.js` imports only turbo
- Propshaft (single `application.css`, `qf-`-prefixed hand CSS), no bundler, no Tailwind
- Auth: Rails 8 `Authentication` concern (DB `sessions`, signed permanent cookie) + `bcrypt` (`has_secure_password`, min length 12) + Google OAuth (`omniauth-google-oauth2`, POST-only, CSRF-protected, `verified_email` gate) + email confirmation via `generates_token_for`
- Infra adapters: Solid Cache/Queue/Cable (cable: async dev / test / redis prod). Zero custom jobs (`ApplicationJob` empty)
- Mailers: `RegistrationMailer` (confirmation), `PasswordsMailer` (reset)
- Pinned workaround: `json < 3` (ActiveSupport 8.1.3.1 calls `JSON.parse` positionally)
- CI (`bin/ci`, GitHub `ci.yml`): rubocop (omakase) → bundler-audit → importmap audit → brakeman (`--exit-on-warn --exit-on-error`) → `rails test` → `db:seed:replant`. System tests scaffolded but commented out of CI

## Architecture

- Classic server-rendered Rails MVC, no API. Entry: `root home#show`; nested `questions/{attempts,comments>approve,reports}`; singular `session/leaderboard/my_questions/profile`; `ui-kit` showcase; `/up` healthcheck
- Data flow: Controller → ActiveRecord (+ `before_create`/`before_validation` callbacks) → ERB. No service/form/decorator layer
- Business logic lives in models + controllers: choice grading in `Attempt#grade_choice!` (`before_create`), option compaction/validation in `Question`, visibility scoping in `QuestionsController` (`visible_attempts`, `respondent_names`, `visible_comments`)
- Access gate: single predicate `privileged?` = author-or-admin, reused across show/edit/update/destroy + comment approve. `Current` (`CurrentAttributes`, session-delegated user)
- Domain rules from code: one Attempt per user per Question (unique index, immutable); choice verdicts derived inline, text/code stay `pending` for external Jury (not in Rails); comments premoderated (`pending → approved`) or auto-open after deadline; `open?/closed?` derived from `deadline` only
- Roles: `admin` bool (global), `display_role` cosmetic (admin-set via `grant_role`, never mass-assigned). Trustee promised in CONTEXT/README, absent in schema/code (see `.scratch/trustee/spec.md`)

## Conventions (Observed)

- Error handling: no `rescue_from`; per-action `redirect_back/alert` with `errors.full_messages.to_sentence`; `head(:forbidden)` for authz denials; single `rescue InvalidSignature` on token accept. 403s bare (no custom page beyond static 400/404/422/500)
- Params: Rails 8.1 `params.expect` throughout (incl. guard for empty credential filter in `ProfilesController`)
- Views: ERB + Turbo (`turbo_stream_from` on question for comments), `form_with`, tab via query param; inline `onclick`/`onkeydown` present (CSP-hostile)
- Ruby: omakase style, `it` one-liners, explicit `# ponytail:` rationale comments, RU user-facing strings + EN code/comments
- Testing: minitest, `fixtures :all`, parallelized; SimpleCov branch gate 90/90 (line+branch); 14 controller tests + 3 model tests + 1 system test; `COVERAGE=false` escape hatch for browser runs
- Mailer default `from@example.com` still placeholder; Gmail SMTP via env (`SMTP_LOGIN`/`GMAIL_APP_PASSWORD`, `APP_HOST`)

## Signals / Active Considerations

- Trustee gap: biggest spec-code drift; `.scratch/trustee/` tickets 01 (join + gate) / 02 (grant/revoke) unstarted
- `HomeController` ILIKE interpolates `%#{@q}%` — needs `sanitize_sql_like`; brakeman green today, fix before Attacks
- Leaderboard + profile rank rebuild full `GROUP BY` + Ruby sort per request; fine at current scale, SQL window-function candidate later
- Stimulus claimed but unused: either drop gem or move inline JS (clipboard share, Enter-to-send) into a controller
- `User.find_or_create_by_omniauth` non-atomic find-then-create under unique indexes — race returns 500, retry wrapper candidate
- No structured logging / metrics; observability = `/up` + silenced healthcheck path only
- `tags` string-array doubles as difficulty (`DIFFICULTIES` subtracted for topics) — works, fragile if tag vocab grows
