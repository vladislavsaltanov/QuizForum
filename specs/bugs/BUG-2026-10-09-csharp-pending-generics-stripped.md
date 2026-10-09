# BUG-2026-10-09T1215: C# check stuck pending + `List<int>` renders as `List`

## Problem

- C# attempt stays `pending` with empty grading columns (`code_total` nil).
  Author sees "sent for check", no verdict ever arrives. Python attempts on
  other questions grade fine. Reproduced live: question 78 (c#), attempts
  39/40 pending, nil columns; direct `run_check` with `c#` returns nil.
- Code containing generics (`List<int>`) displays truncated (`List`).
  Reproduced: `simple_format("List<int> foo")` renders `<p>List foo</p>`.
- Expected: C# grades like python; code renders literally.

## Root Cause Analysis

Two stacked defects behind the C# symptom, one behind the display symptom.

1. Stale coderunner reused forever (primary C# cause). `bin/dev` reuses a
   live runner as-is. The running process predates compiled-language support:
   `/up` reports only python/node/ruby and no `runners_mtime`; sources on
   disk (Oct 9) are newer than the process (log Oct 8). `c#` POSTs get 400
   unknown-language, the client maps that to nil, the job raises CheckFailed
   and backs off (`retry_on`, polynomial waits x5), then the attempt sits
   pending with nil columns. No auto-recovery: recurring recheck needs a
   dispatcher dev never runs.
2. Bad C# reference accepted at creation (stacked). Question 78 reference is
   `int solve(int[] xs)` (lowercase). The runner only accepts `Solve`. The
   create-time dry run fails open on nil, so with a stale runner anything is
   accepted; with a fresh runner this reference still yields needs_review,
   never a verdict. The form hint says the method must be `solve`, wrong for C#.
3. `simple_format` strips generics (display cause). It sanitizes: unknown tags
   like `<int>` are dropped, not escaped. Every code body rendered through it
   (attempt body, reference, explanation) loses generic suffixes. Verified in
   runner. `sanitize: false` is not the fix: it emits raw `<int>` into HTML
   (invisible element + injection surface).

Security impact: LOW (display stripping only hides text; no exploit path
identified; the `sanitize: false` non-fix would open one).

Risk level: Medium (data afficher + grading stall, no data loss).

## TDD Fix Plan

1. **RED**: view test posts attempt body `List<int> x`, asserts response shows
   `List&lt;int&gt;`.
   **GREEN**: code attempts render escaped literal (`h` in `pre`), prose keeps
   `simple_format`. Cover reference block on code questions the same way.
   **verify**: `bin/rails test test/integration/`
2. **RED**: shell probe asserts `bin/dev` restarts a runner whose `/up` lacks
   `runners_mtime` or whose mtime is older than sources.
   **GREEN**: `bin/dev` compares `/up` version stamp, kills stale process,
   boots fresh before Rails.
   **verify**: manual restart + `curl /up` shows full runtimes.
3. **RED**: C# form test asserts hint names `Solve` for c# questions.
   **GREEN**: hint picks `Solve` when c# is the (only) allowed language.
   **verify**: `bin/rails test test/controllers/questions_controller_test.rb`

**REFACTOR**: none expected.

Note: question 78 reference needs a data fix (`Solve`, valid class shape);
separate from code, do via console/edit form after deploy.

## Acceptance Criteria

- [ ] `List<int>` survives submit → display round-trip literally
- [ ] Fresh `bin/dev` boot grades C# (runner `/up` lists dotnet)
- [ ] C# question form hints `Solve`
- [ ] All new tests pass
- [ ] Existing tests still pass

## Resolution

<!-- filled in by validate-fix -->
