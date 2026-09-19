# QuizForum

An open question bank: anyone publishes a Question with a hidden Reference Answer and a Deadline; others answer blind. After the Deadline everything opens — reference material, all attempts, verdicts, comments. An AI Jury grades text attempts; AI-assisted moderation keeps comments clean.

## Language

### Content

**Question**:
A task published by an Author: title, body, answer type (text | single_choice | multiple_choice), a Deadline, and tags. Its reference material is hidden until the Deadline.
_Avoid_: quiz, task, упражнение

**Reference Answer**:
The authoritative correct answer for a text Question. Hidden from everyone except the Author and Trustees until the Deadline; public after.
_Avoid_: эталон, solution, key

**Option**:
One predefined choice in a choice-type Question. Its `is_correct` flag is hidden until the Deadline.
_Avoid_: answer variant, вариант

**Tag**:
A unique label used to filter Questions (subject, difficulty). A Question's status (open/closed) is derived from its Deadline, never from a tag.
_Avoid_: категория, subject, difficulty (as a column)

**Comment**:
A short clarifying note on a Question. Premoderated: hidden by default until approved, or until the Deadline opens it.
_Avoid_: reply, discussion, уточнение

### Participation

**Attempt**:
A user's answer to a Question — exactly one per user per Question. Immutable once created — no edits, no deletions by the respondent.
_Avoid_: ответ, submission, answer record

**Verdict**:
The outcome of an Attempt: pending | correct | incorrect | partial. Assigned by the Jury (for text) or derived from Option correctness (for choice types).
_Avoid_: score, grade, result, оценка

**Respondent**:
A user who has submitted an Attempt. Before the Deadline only their identity (that they answered) is visible — never their answer text.
_Avoid_: participant, участник

**Author**:
The user who published a Question. Any registered user can be one; "teacher"/"student" are personas, not privileges.
_Avoid_: teacher, преподаватель (as an access-control term)

**Trustee**:
A user granted Author-level view access to one specific Question (attempts + Reference Answer), regardless of the Deadline.
_Avoid_: admin, moderator, доверенное лицо

**Leaderboard**:
User ranking by count of correct Verdicts across revealed Questions.
_Avoid_: rating, top, рейтинг

### Timing & access

**Deadline**:
The instant a Question closes. Before it: identities visible, texts and verdicts hidden. After it: everything is public.
_Avoid_: due date, close date

**Reveal**:
The automatic post-Deadline opening of a Question's reference material, all Attempts, Verdicts, and Comments. Requires no manual action.
_Avoid_: unlock, раскрытие

**Moderation**:
The approval flow keeping Comments hidden until an Author/Trustee approves them (pending → approved) or the Deadline opens them.
_Avoid_: premoderation, премодерация

### AI

**Jury**:
The external AI model (openjev) that evaluates text Attempts against the Reference Answer and returns a Verdict. Runs in a separate inference service, never inside the Rails process.
_Avoid_: judge, grader, жюри

**display_role**:
Cosmetic label on a user ("доцент кафедры"). Carries no access-control meaning.
_Avoid_: role (for authorization checks)
