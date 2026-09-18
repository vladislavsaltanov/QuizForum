# Issue tracker: Local Markdown + GitHub

Issues and specs for this repo live as markdown files in `.scratch/`. The GitHub
remote (`vladislavsaltanov/QuizForum`) is active, so issues are mirrored to
GitHub Issues via the `gh` CLI.

## Conventions (local, primary)

- One feature per directory: `.scratch/<feature-slug>/`
- The spec is `.scratch/<feature-slug>/spec.md`
- Implementation issues are one file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01`, never a single combined tickets file
- Comments and conversation history append to the bottom of the file under a `## Comments` heading

## GitHub mirror

- **Mirror an issue**: `gh issue create --title "..." --body "..."` (heredoc for multi-line bodies), then paste the issue URL back into the local file
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq`
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v`; `gh` does this automatically when run inside a clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

## When a skill says "publish to the issue tracker"

Create the local file under `.scratch/<feature-slug>/` (creating the directory if needed), then mirror it to GitHub if the remote is reachable.

## When a skill says "fetch the relevant ticket"

Read the local file at the referenced path. If only a GitHub number is given, run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a file with one **child** file per ticket.

- **Map**: `.scratch/<effort>/map.md` (the Notes / Decisions-so-far / Fog body).
- **Child ticket**: `.scratch/<effort>/issues/NN-<slug>.md`, numbered from `01`, with the question in the body. A `Type:` line records the ticket type (`research`/`prototype`/`grilling`/`task`); a `Status:` line records `claimed`/`resolved`.
- **Blocking**: a `Blocked by: NN, NN` line near the top. A ticket is unblocked when every file it lists is `resolved`.
- **Frontier**: scan `.scratch/<effort>/issues/` for files that are open, unblocked, and unclaimed; first by number wins.
- **Claim**: set `Status: claimed` and save before any work.
- **Resolve**: append the answer under an `## Answer` heading, set `Status: resolved`, then append a context pointer (gist + link) to the map's Decisions-so-far in `map.md`.
