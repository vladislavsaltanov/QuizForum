# QuizForum

Open question bank. Any user publishes a Question with a hidden Reference Answer and a Deadline. Others answer blind. After the Deadline, the Question opens: reference material, all Attempts, Verdicts, Comments.

## How it works

- Author publishes a Question: title, body, answer type, Deadline, tags.
- Each user submits one Attempt per Question. Attempts are immutable.
- Before the Deadline: only Respondent identities are visible. Texts and Verdicts stay hidden.
- After the Deadline (Reveal): everything becomes public. No manual action required.
- Trustee gets Author-level view on one Question, before the Deadline.

## Answer types and Verdicts

Answer types: `text`, `code` (with language), `single_choice`, `multiple_choice`.

Verdicts: `pending`, `correct`, `partial`, `incorrect`.

- Choice Questions grade at once from Option correctness. Exact match gives `correct`. Partly right gives `partial`.
- Text and code Attempts stay `pending`. External Jury grades them later.

## Roles

- Any registered user can publish a Question. Teacher and student are personas, not privileges.
- Trustee: per-Question access grant, not a global role.
- `display_role` is a cosmetic label. It grants no access.
- Admin flag exists for site administration only.

## Comments and Moderation

Comments are premoderated. A Comment stays hidden until the Author approves it or until the Deadline opens it.

## Leaderboard

Ranking by count of `correct` Verdicts on revealed Questions.

## Stack

- Ruby 4.0.7, Rails 8.1.3.1, PostgreSQL, Hotwire (Turbo + Stimulus), Importmap
- Auth: `bcrypt` sessions, Google OAuth (`omniauth-google-oauth2`), email confirmation
- Background: Solid Cache / Queue / Cable. Assets: Propshaft. Deploy: Kamal, Thruster, Docker

## Quick start

```bash
bin/setup
bin/rails db:seed   # demo bank: 3 users, 7 questions
bin/dev             # app on http://localhost:3000
```

Run tests:

```bash
bin/rails test
bin/rails test:system
```

Lint and security:

```bash
bin/rubocop
bin/brakeman
bin/bundler-audit check
```

## Configuration

Copy `.env.example` to `.env`. Required keys:

| Key | Purpose |
| --- | ------- |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Google OAuth |
| `SMTP_LOGIN` / `GMAIL_APP_PASSWORD` | Confirmation and password mail |
| `APP_HOST` | Host name used in email links |

## Domain language

Full glossary lives in `CONTEXT.md`. Use its terms: Question, Reference Answer, Option, Attempt, Verdict, Respondent, Author, Trustee, Deadline, Reveal, Moderation, Jury, Leaderboard. Avoid synonyms: quiz, submission, score, rating.

## Issues

Issues live in `.scratch/<feature>/`, mirrored to GitHub Issues (`gh`). See `docs/agents/issue-tracker.md`.

## License

MIT. See `LICENSE`.
