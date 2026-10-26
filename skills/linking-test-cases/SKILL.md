---
name: linking-test-cases
description: >-
  Link a repository's autotests to Qase test cases by meaning: propose a mapping
  for confirmation, write the confirmed case IDs into the test code in each Qase
  reporter's own syntax, and mark the linked cases Automated. Use when the user
  asks to link, map, match, or connect autotests or automated tests to Qase cases;
  to add Qase IDs, QaseId annotations, or case IDs to tests; why tests don't match
  their cases in Qase; or why automated results land in Qase as new cases instead
  of the existing ones.
---

# Linking Test Cases

A Qase reporter can attach an automated result to a case only when the test carries
that case's ID in code. This skill reads the repository's autotests and the project's
cases, matches them **by meaning** — what the test body does against the case's
title, steps, preconditions and suite, not title equality — and, once the user has
confirmed the mapping, writes the IDs into the tests in the syntax of the reporter the
repository uses.

It is the one skill in this plugin that edits code, so every write
sits behind one rule: **nothing in the code and nothing in Qase changes until the user
has seen and confirmed the mapping.** Steps 1–8 only read, apart from writing the
review file and appending it to `.gitignore`; steps 9–11 write.

## Prerequisites

- A **git repository** with autotests in it.
- A **project code**. If the user didn't give one, ask — never guess. One project per
  run.
- QQL access (Teams/Enterprise) for the case inventory.
- **Read the plugin's `references/qql.md` before composing any QQL query.** It sits two
  levels up from this skill's directory (`../../references/qql.md`) — not in this
  skill's own `references/`, which holds only reporter syntax. Field names are not
  uniform across entities, and a wrong one is a hard error rather than an empty
  result. `automation` is `0` = Manual, `1` = To be automated, `2` = Automated.
- The reporter syntax lives in this skill's `references/<file>.md`, one file per
  ecosystem. **Syntax comes only from those files — never from reporter docs or
  memory.** Several reporter docs show markers the reporter silently ignores.

## Tools

- `qase_project_context` — the suite tree. Call first.
- `qql_search` — the case inventory, in batches.
- `qase_get` — steps and preconditions of shortlisted candidates; existence and live
  `automation` before any write; `updated` after a write.
- `qase_case_upsert` — set `automation` on one case at a time (there is no bulk
  update). Only in step 10.
- `qase_case_bulk_create` — create cases for tests the user chose to create them for.
  Only in step 10.
- `Bash`, `Read`, `Grep`, `Glob`, `Edit`, `Write` — detection, the tests, the marker
  edits, and the two files under `.qase/`.

Read `qase_tool_help` for a write tool before its first call. Never call a `*_delete`
tool — the plugin's hooks block them anyway, and this skill deletes nothing in Qase
or in code. It never installs or configures a reporter, never runs the tests, never
edits a case's title or steps, and never commits.

**Questions are plain chat.** Do not rely on a structured question tool — it does not
exist in every client this plugin runs in. The confirmation is a chat summary plus an
editable file.

## Step 1: Project and scope

Get the project code (ask if missing). Then settle the scope:

1. the whole repository against the whole project;
2. by test directory — a path or glob;
3. by Qase suite(s);
4. both together — e.g. `tests/checkout` against suite *Checkout*.

Always offer this menu and wait for the answer. The only exception: the request
already names a scope — "the whole repo", a directory, a suite — then use it and say
which scope you took.

## Step 2: Detect the stack

Find the manifests anywhere in the repository (skip `node_modules`, `vendor`,
`.git`, build output) and map each to its reference file:

| Manifest | Reference |
|---|---|
| `package.json` | `references/javascript.md` |
| `pyproject.toml`, `requirements*.txt` | `references/python.md` |
| `pom.xml`, `build.gradle`, `build.gradle.kts` | `references/jvm.md` |
| `*.csproj` | `references/dotnet.md` |
| `go.mod` | `references/go.md` |
| `composer.json` | `references/php.md` |

**Load only the reference files for stacks you found.** In each, every framework is a
`### <Framework>` section with bold labels: `**Detect:**` (the reporter package),
`**Import:**`, `**Write:**` (the canonical marker), `**Multi-ID:**` (a form, or
`not supported`), `**Also valid:**`, `**Never write:**`, `**Scope:**`, and sometimes
`**Not verified — don't write:**`.

Determine the test frameworks from the manifests **and** the test files themselves
(a `test_*.py` importing `pytest`, a `*.feature` file, `*_test.go`, `*.test.ts`) — a
directory of tests can have no manifest of its own. A repository may hold several
frameworks; each gets its own syntax. Check every manifest kind in the table before
calling a reporter missing: a `*.feature` file may be Java Cucumber (reporter in
`pom.xml` or a Gradle file) or CucumberJS (reporter in `package.json`).

**Missing reporter:** a framework whose `**Detect:**` package is absent from the
manifest that governs those tests is reported as *reporter missing* and gets **no**
markers — not in the proposal, not in step 9, even if a review file accepts a row
for it. Never install the reporter or suggest a marker that would do nothing.

## Step 3: Load state

The state file is `.qase/links.json` — a cache plus the user's past decisions, not
the source of truth (the IDs in code are):

```json
{"version": 1, "project": "DEMO", "storage": "committed|local",
 "entries": [{"test": {"file": "tests/test_x.py", "name": "test_y"},
              "fingerprint": "sha256:<hex>", "cases": [4],
              "case_updated": {"4": "<ISO-8601>"},
              "status": "verified|rejected|no-case-wanted|case-declined|qase-pending",
              "date": "YYYY-MM-DD"}]}
```

- **Missing or unparsable** → a full run. Say so in one line and carry on; never
  fail on it. Never overwrite an unparsable file silently — say it will be replaced
  in step 11.
- A `project` that differs from this run's → ignore its entries and say so.
- **First run** (no file): ask where to keep it — `committed` (in the repo, shared
  with the team and CI) or `local` (same path, gitignored). Ask it in the step 8
  message rather than stopping here; nothing writes the state file before step 11.

## Step 4: Inventory

**Tests in scope.** For each framework, enumerate its tests: test functions and
methods; for BDD, scenarios; for Newman, the `pm.test` blocks in collections; for
Robot, test cases. Record `path:line name`, the test's source block (from its first
decorator, annotation or tag line to its end), and any Qase marker already on it in
any form the reference lists — `**Write:**`, `**Multi-ID:**`, `**Also valid:**`,
`**Never write:**`.

**Fingerprint** each test that has a state entry, to compare in step 5: sha256 of the
source block with every whitespace run collapsed to one space.

```bash
hash="shasum -a 256"; command -v shasum >/dev/null || hash=sha256sum
sed -n "${first},${last}p" "$file" | tr -s '[:space:]' ' ' | $hash | cut -d' ' -f1
```

Stored as `sha256:<hex>`. If hashing is unavailable — no shell, no hash tool — still
write the state, with `fingerprint: null`. A null fingerprint never matches, so step 5
re-examines that pair, but the entry's status and the user's decision are kept.

**Cases in scope.** `qase_project_context` once for the suite tree, then QQL in
batches — never one call per case:

```
SELECT (COUNT(*)) entity = "case" and project = "DEMO" and suiteTree = "Checkout"
entity = "case" and project = "DEMO" and suiteTree = "Checkout"
```

Count first; then fetch full-entity rows (no `SELECT`) with `limit` 100, paging by
offset. Take `id`, `title`, `suite`, `automation`, `updated`. `suiteTree` takes in a
suite's descendants; `suite = "X"` matches *every* suite with that title. Full-entity
rows carry hydrated, live values; a `SELECT (…)` projection reads an index that can
lag minutes to days — so take `automation` and `updated` from full-entity
(hydrated) rows or `qase_get`, never from a QQL projection. If
the scope holds more than about 1,000 cases, propose narrowing by suite before
reading them all.

`steps` is **not** a QQL case field. Read steps and preconditions with `qase_get`
**only for shortlisted candidates** (step 7), never for the whole inventory. Keep each
case you read; several tests often share candidates.

## Step 5: Skip what is unchanged

For each test with a state entry:

- `verified`, and its stored `fingerprint` **and** every `case_updated` timestamp
  still match (the test's current fingerprint; each case's `updated` from the
  full-entity (hydrated) rows or `qase_get`, never a projection) **and** the code
  still carries exactly those IDs → skip it. Count
  it as *unchanged since <date>*.
- `verified` but anything differs → re-examine; it goes through step 6 like any test
  with an ID.
- `rejected` → never re-propose that test–case pair. Other candidates for the test are
  still fair.
- `no-case-wanted` → never propose anything for that test again.
- `case-declined` → never re-offer creating a case for it; a link to a case that
  appears later may still be proposed.
- `qase-pending` with case IDs → the code is linked but the Qase update was
  deferred. Re-verify the pair, then offer the deferred update again in step 10.
- `qase-pending` with `cases: []` → the user chose `create` but deferred Qase. Don't
  re-propose the test as new: list it in the review file under *Tests without a case*
  with `create` pre-filled and the reason "creation deferred from <date>".

A renamed or moved test misses its entry and is simply examined afresh.

## Step 6: Verify existing IDs

For each ID already in code, read the case (`qase_get`, batched with the step 7 reads)
and compare its steps with the test body. Classify:

- **confirmed** — the case exists and describes what the test does;
- **case not found** — deleted or never existed;
- **probably the wrong case** — the meaning doesn't match; propose the right one if
  step 7 finds it;
- **a better case exists** — the current case fits loosely and another fits clearly.

Existing IDs are **never** changed without the same confirmation as new links.

Check the code side too, against the framework's reference section:

- a marker matching that framework's `**Never write:**` line is one the reporter
  silently ignores (e.g. `@QaseId=1,2` in Java Cucumber, `qase(1, …)` in Vitest,
  `#[QaseId]` on a Pest closure, a Jest suffix with spaces) — flag it with the fix in
  the `**Write:**` or `**Multi-ID:**` form;
- a marker in a form under `**Not verified — don't write:**` — flag it, and propose a
  verified form only if the section has one;
- a **multi-project** marker (the multi-project form in `**Also valid:**`) — report
  it and leave it untouched; multi-project mapping is out of scope.

Confirmed IDs with nothing to fix and a case already Automated need no row; count
them, keep the case's `updated` from this read, and record them `verified` in step 11
so the next run skips them. A confirmed ID whose case is not Automated gets a row, so its update can be
offered in step 10.

## Step 7: Match

For each unlinked test in scope, find candidate cases by meaning:

1. **Prefilter** by suite (suite title against the test's path, file, describe/class
   block), path, and words shared between the test name and case titles. Keep a
   handful of candidates per test.
2. **Read the bodies:** the test code, and the candidates' steps and preconditions
   (`qase_get`).
3. **Decide**, with a confidence and a one-line reason:
   - `high` — the steps and the test body check the same behaviour, and no other
     candidate fits comparably;
   - `medium` — same feature and intent, but steps are missing or partial, or another
     candidate fits nearly as well;
   - `low` — only the title or suite overlaps; the behaviour is not confirmed.

Rules:

- **Hand-written over reporter-created.** A case a reporter created on an earlier run
  usually has a title equal to the test name and no steps. When both kinds match,
  propose the hand-written one and name the other as a likely duplicate in the
  reason. Never delete or merge cases.
- **Many-to-many** is fine: one case from several tests (parameterized variants), and
  several cases on one test (an e2e flow) — the latter **only** where the framework's
  `**Multi-ID:**` is not `not supported`; otherwise propose one and say why.
- **No marker that needs restructuring.** If the only way to carry an ID is to rewrite
  the test — a plain Go `func TestX(t *testing.T)` without `qase.Test` — report it as
  *reporter not wired for this test*; don't wrap it. A runtime-call marker (Pest
  `qase()->caseId()`, Kaspresso `Qase.id()`) or TestCafe's `.meta(...)` is a marker,
  not restructuring.
- Never propose a form listed under `**Not verified — don't write:**`. Use the
  verified alternative the section names, or report the test.
- A test with no plausible case goes to *Tests without a case*. A case in scope that
  no test covers goes to *Cases with no test*.

## Step 8: Confirm — then stop

Write the full mapping to `.qase/link-review.md`, then print a short chat summary,
then **stop and wait for the user**. No code edit and no Qase write happens in this
turn.

### The review file

```markdown
# Qase link review — WEB

Fill the Decision column: `accept`, `reject`, `edit: <id>[,<id>…]`, `create`, `skip`,
or leave it empty (undecided). Then reply `done` in chat.

## New links

| # | Test | Case(s) | Confidence | Reason | Decision |
|---|---|---|---|---|---|
| 1 | tests/test_login.py:18 test_locked_account | 41 Login: locked account is refused | high | Logs in to a locked account and asserts the refusal message, as the steps do | accept |

## Existing IDs

| # | Test | Case(s) | Confidence | Reason | Decision |
|---|---|---|---|---|---|
| 2 | tests/test_login.py:9 test_password_reset | 55 → 43 Login: reset link is emailed | medium | Probably the wrong case: 55 covers sign-up; the test requests a reset link | |

## Tests without a case

| # | Test | Case(s) | Confidence | Reason | Decision |
|---|---|---|---|---|---|
| 3 | tests/test_login.py:30 test_session_expiry | — | — | No case covers session expiry; `create` to add one | |

## Cases with no test

| # | Test | Case(s) | Confidence | Reason | Decision |
|---|---|---|---|---|---|
| 4 | — | 47 Login: sign in with SSO | — | No test in scope exercises SSO | |

## Qase update

Decision:
```

Format rules:

- `Test` is `path:line name`. `Case(s)` is `<id> <title>`, several separated by `; `;
  for an existing ID, `<current> → <proposed> <title>`, or `<current> <title>` when
  only its status or marker form is at issue. Escape `|` in titles as `\|`.
- Row numbers are unique across the whole file, not per group.
- `high` rows are pre-filled `accept`; every other Decision starts empty. Never
  pre-fill `create`.
- The `## Qase update` line `Decision:` is left empty, for `now` or `later`.

What each decision means:

| Decision | New links | Existing IDs | Tests without a case |
|---|---|---|---|
| `accept` | write the proposed ID(s) | apply the proposed fix | — |
| `reject` | write nothing; record `rejected` for the pair | keep the code as is; record `rejected` for the proposed case | record `case-declined` |
| `edit: <id>[,<id>…]` | write these IDs instead | replace the marker with these IDs | link to these IDs |
| `create` | — | — | create a case, then link it |
| `skip` | leave the test unlinked for good: `no-case-wanted` | keep the code as is; nothing recorded | `no-case-wanted` |
| empty | undecided: nothing written or recorded; asked again next run | same | same |

*Cases with no test* rows are information: nothing is written for them, whatever
their Decision says.

Add `.qase/link-review.md` to `.gitignore` — and `.qase/links.json` too once storage is
`local`. Create `.gitignore` if missing; append the line only if it isn't already
there; never rewrite the file.

### The chat summary

Counts per group, then only the rows that need attention: every `medium`/`low` row,
every existing-ID problem, missing reporters, tests that need restructuring. A
question a reference file raises about a row (Newman's per-`pm.test` scope, say) goes
in that row's Reason and in this list — never a separate stop. Then:

- the path to the review file, and the two ways to answer — reply in chat
  (`accept all except 12, 40`, `reject 7`, `13: edit 51`, `create 20, 21`) or edit the
  file and reply `done`;
- on a first run, the storage question: `committed` or `local`;
- that Qase changes immediately when updated, while the code change lands only when
  merged — so they can also answer `now` or `later` for the Qase update;
- a plain statement that nothing has been written to code or Qase yet.

### The next turn

- **Chat answers** → apply them to the review file's Decision column first, so file
  and state agree. "Accept all" covers *New links* and *Existing IDs* rows; *Tests
  without a case* need an explicit `create`. Rows excepted from "accept all" become
  undecided, not rejected, unless the user says reject.
- **`done`** → re-read `.qase/link-review.md` and take its decisions as written. An
  unrecognised decision is undecided; list it in the report.
- **Applying an earlier review:** if `.qase/link-review.md` already exists with
  decisions filled in and the user asks to apply it, skip steps 4–8 and go straight
  to step 9 — after the parts of steps 1–3 that step 9 needs (project code from the
  file title or the state file, the full stack detection of step 2, state). A file whose first line is
  `Applied: <date>` was already applied (step 11): never apply it again — say so and
  offer a fresh run instead, which replaces it. If an unstamped file exists but the
  user started a fresh run, say it holds unapplied decisions and ask whether to apply
  it or replace it.

## Step 9: Write the code

Work from the decisions only. For every test, gather the IDs from its `accept` and
`edit:` rows (a `reject` row on the same test adds nothing), then:

1. **Confirm each case exists** with `qase_get`. An unknown ID is not written; report
   it. Keep the reads — step 10 needs each case's live `automation`.
2. **Re-check the framework**: reporter present (step 2), the marker needs no
   restructuring, several IDs only where `**Multi-ID:**` allows. A row that fails is
   not written; report why.
3. **Skip** a test that already carries exactly those IDs in any `**Write:**`,
   `**Multi-ID:**` or `**Also valid:**` form — never add a second marker.
   **Merge** a new ID into a test that already carries a confirmed one: the new IDs
   and the confirmed IDs go into one marker in the `**Multi-ID:**` form, replacing
   the old marker in place — never drop a confirmed ID, never add a second marker.
   Where `**Multi-ID:**` is `not supported`, write nothing and report it.
4. **Choose the form.** If the repository already uses a valid form for this framework
   (one in `**Write:**`, `**Multi-ID:**` or `**Also valid:**`), follow it; otherwise
   use `**Write:**`, or `**Multi-ID:**` for several IDs. Never a `**Never write:**`
   form, never a `**Not verified — don't write:**` one.
5. **Edit minimally.** An existing-ID fix replaces the old marker in place. Add the
   `**Import:**` line only if the file lacks it, next to the file's other imports.
   Touch no other line: no reformatting, no reordering, no renaming, and keep the
   file's quoting, indentation and line endings.

`create` rows get their IDs in step 10 and come back here for the same edit.

Show `git diff --stat` afterwards. Do not commit.

## Step 10: Write Qase

Follow the `## Qase update` decision (or the chat answer):

- **`later`** → no Qase write at all, including case creation. Record each linked
  entry whose case has a pending Qase write as `qase-pending`; each `create` row
  gets a `qase-pending` entry with `cases: []`, and no IDs are written.
- **empty** → ask, explaining that Qase changes now while the code lands on merge,
  and wait.
- **`now`** → continue.

Collect every question first and ask them in **one** message, then **stop and wait
for the answers**. Write nothing that depends on an unanswered question — never flip
a Manual case, change an old case or create a case before the user has answered.
Writes that depend on no question may go ahead once the answers are in. The
questions:

- Cases to set Automated: those linked in step 9, plus confirmed existing IDs whose
  case isn't Automated and whose row was accepted. Use the live `automation` read in
  step 9: `2` → nothing; `1` → update; **`0` (Manual) → ask first**, per case — it
  was a deliberate team choice.
- A link removed or replaced in step 9, whose old case no other test still carries:
  **ask** what its `automation` becomes — leave / To be automated / Manual.
- `create` rows: propose a title and steps derived from the test, and the suite that
  plainly matches the test's area; **ask for the suite when it isn't obvious**.

Then:

1. Create cases with `qase_case_bulk_create` (one call, `automation` = Automated),
   and write their new IDs into code as in step 9. First drop any `create` row whose
   test already carries an ID in code — a case created twice can never be deleted;
   report the row instead.
2. Set `automation` with `qase_case_upsert`, **one case per call**, only the
   `automation` field.
3. **Re-read every case you wrote with `qase_get`** and keep its `updated`. Your own
   write changes `updated`, so a value taken before the write would make the next
   run re-examine every pair just linked. Take it from this `qase_get`, never from
   a QQL projection, which lags.

A write that fails: record that entry `qase-pending`, carry on, report it.

## Step 11: Report and save state

**Write `.qase/links.json`.** Keep entries for tests outside this run's scope as they
were. For each test touched by this run:

- linked and Qase written (or nothing to write) → `verified`, `case_updated` from the
  step 10 re-read, or from the step 9 read when Qase was not written;
- linked, Qase deferred or failed → `qase-pending`; `create` deferred →
  `qase-pending` with `cases: []`;
- `reject` → `rejected` with the rejected case(s); `reject` on a test without a
  case → `case-declined`; `skip` on a new link or a test without a case →
  `no-case-wanted`;
- confirmed existing IDs with nothing to fix (no row, step 6) → `verified`, with
  `case_updated` from the step 6 read;
- undecided rows, and `skip` on an existing ID → no new entry.

A test can hold more than one entry — say `verified` for case 1 and `rejected` for
case 3.

`fingerprint` is computed now, on the file as written — the marker is part of the
block. `date` is today. Keep `storage` as chosen; if it is `local`, make sure
`.qase/links.json` is in `.gitignore`.

**Stamp the review file.** Insert `Applied: <YYYY-MM-DD>` as the first line of
`.qase/link-review.md`, so it is never applied twice — a second apply would re-run its
`create` rows.

**Then report in chat**, in this shape:

```
## Linking — <PROJECT> · <scope>
_Generated by Qase Quality Supervisor · linking-test-cases skill_

Stack: <framework → reporter, reference file>; reporter missing: <frameworks, or none>

### Linked
- <path:line name> → <ids> (<form used>)

### Existing IDs
- Confirmed: <n> · Fixed: <list> · Flagged, unchanged: <list>

### Qase
- Set Automated: <ids> · Left as is by request: <ids> · Pending (later / failed): <ids>
- Created: <id title, suite> — or: not updated, by request

### Not written
- <row/test> — <unknown case ID | reporter missing | needs restructuring | unverified syntax | multi-project marker | Multi-ID not supported>

### Skipped
- Unchanged since last run: <n> · Undecided: <n> · Rejected: <n> · No case wanted: <n>
- Likely duplicates (reporter-created): <ids> — never deleted or merged

State: .qase/links.json (<committed|local>) · <n> entries
Next: review `git diff`, run the suite, commit with your change.

---
_Generated by Qase Quality Supervisor · linking-test-cases skill_
```

Leave out a section that has nothing in it, except **Not written** when something
wasn't — that list is what the user must act on.

## Honesty notes

- Matching by meaning is a judgement. A confidence is an estimate, not a proof: never
  pre-accept a `medium` or `low` row, and give the reason that would let the user
  overrule you.
- Say what you did not do: never claim Qase was updated when the decision was
  `later` or a write failed, and never claim the markers work — the tests were not
  run. The reporter only proves the link on the next run.
- A QQL projection can lag the live case; decisions that turn on one case —
  existence, `automation`, `updated` — come from full-entity (hydrated) rows or
  `qase_get`, never from a QQL projection.
- If the scope was too large to examine whole, say which part was examined. A
  partial run presented as complete is worse than an admitted gap.
