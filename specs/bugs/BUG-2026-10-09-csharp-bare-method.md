# BUG-2026-10-09T1310: C# bare method style rejected

## Problem

- Attempts still `pending` after the runner fix when the runner was down in
  the submit window: retries burn out, dev runs no recheck dispatcher, rows
  sit pending with nil columns. Reproduced: attempt 41 submitted in the gap.
- Modern C# without `class Solution` (`int solve(int[] xs) {...}`) never
  grades: no `Solution` type for the harness; lowercase name mismatches the
  `Solution.Solve` call; bare methods default to private (`CS0122`).

## Root Cause Analysis

1. Silent pending after retry exhaustion. `CheckFailed` retries 5 times with
   polynomial waits, then the attempt is abandoned with nil grading columns
   and no signal. Re-driving the same job grades fine.
2. Runner required `class Solution` + `Solve`. Three stacked rejections for
   bare style: missing type, wrong case call, private default accessibility.
   Each surfaced as compile fail or needs_review, never guidance.

Security impact: NONE. No exploit path identified.

Risk level: Low (grading-only, fail-closed to incorrect/review).

## TDD Fix Plan

1. **RED**: live probe — bare `int solve(int[] xs)` grades `correct`.
   **GREEN**: wrap classless code in `Solution`, rename unqualified
   `solve` to `Solve`, default the method to `public`, call static or
   instance per side declaration.
   **verify**: live `run_check` + `AttemptCodeCheckJob.perform_now` → correct.
2. **RED**: c# form test asserts `Solve` hint (exists).
   **GREEN**: hint adds "(class Solution можно не писать)" for c#-only.
   **verify**: `bin/rails test test/controllers/questions_flow_test.rb`

**REFACTOR**: none.

## Acceptance Criteria

- [ ] Bare `int solve(int[] xs)` (no class) grades `correct`
- [ ] Class + static `Solve` still grades (no regression)
- [ ] Hint mentions class-optional for c#
- [ ] Full suite green (358 runs)

## Resolution

Fixed in `fix-csharp-toplevel`. Live verified: bare style → correct 34/34;
class style self-check 3/3; suite 358 green. Attempt 41 (gap victim)
re-driven to correct. 39/40 stay incorrect (unsupported `List<int>` type) —
resubmit with `int[]`.
