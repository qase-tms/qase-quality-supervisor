---
name: prioritizing-automation-candidates
description: >-
  Rank a Qase project's manual test cases by how much manual QA time automating
  them would save, recommend at which layer to automate each (e2e, API, unit),
  and — with the team's own effort figures — compute ROI, payback and what a
  budget of engineering hours buys. Use when the user asks which tests or cases
  to automate next; for good automation candidates or a replacement for AIDEN
  Test Advisor; where manual QA time is going; the ROI or business case of
  automating a suite; or "we have N hours for automation, what should we
  automate?". Not for coverage gaps, untested areas, or listing which cases are
  still manual — that is analyzing-test-coverage.
---

# Quality Supervisor — Automation Candidates

Answer one question: **where should the next automation hour go so that it saves the
most manual QA time, and how should that test be automated?** Three stages, in order:

1. **Demand** — how often each manual regression test runs and how much of a tester's
   working time it takes.
2. **Feasibility** — for the tests that take the most time: at which layer to automate
   them, how many tests that means, and what makes it hard.
3. **ROI** — hours saved per year against build and maintenance effort, computed only
   from the team's own effort figures.

The skill invents no effort numbers. Without the team's hours per test it reports manual
time and difficulty, and lets the team price them.

**Read `references/data-sources.md` before the first query.** It holds the verified
QQL and REST forms; parameter formats there are not guessable (`api=0`, not
`api=false`; `from_end_time` as `"YYYY-MM-DD HH:MM:SS"`, not a unix timestamp). For
fields it doesn't cover, the plugin's shared QQL reference sits two levels up from this
skill's directory (`../../references/qql.md`).

## Inputs

| Input | Default | Notes |
|---|---|---|
| Project code | — | Ask if missing. Never guess |
| Regression scope | ask (0.2) | Which runs are regression: a test plan, milestone, run tag, title pattern, or all manual runs |
| Hours per test, by layer | ask (0.2) | Typical hours to write one e2e, API, unit test. Without them: no ROI (Stage 3) |
| Maintenance | ask (0.2) | Share of build effort spent per year keeping a test working. Without it, ROI excludes maintenance and says so |
| Test harnesses | ask (0.2) | Whether automated tests can already read email, receive SMS/OTP codes, pay in a payment sandbox (3DS included), run on mobile devices |
| Budget | none | Engineering hours, optional; needs hours per test |
| Window | 90 days | Widened automatically, see 1.5. Always state the window used |
| Idle cutoff | 30 min | A gap between a tester's results longer than this is a break (1.4) |
| Hourly rate | none | Only then add money columns |

This version does not read the automation repository. Take what the user tells you
about it as automation context (existing page objects, fixtures, covered flows).

Tool names below are bare (`qql_search`, `qase_get`, `qase_api`); your client prefixes
them with the Qase MCP server's name. A tool named here may not be loaded yet: some
clients load only part of a long tool list and keep the rest behind their own tool
search. Find it with that search before concluding it is unavailable.

## Stage 0 — activity, questions, data path

`qase_project_context` is optional here: nothing below needs it, and on a large project
its output can exceed the client's limit.

### 0.1 Is there manual work at all?

One QQL call on `run` (works even where result QQL doesn't):

```
SELECT (isAutotest, COUNT(id), MAX(started)) entity = "run" and project = "CODE" and started >= now("-365d") GROUP BY isAutotest
```

No manual runs (`isAutotest` false) in 12 months → confirm with one REST count, since a
person can also post results into a reporter's run: `GET /v1/result/{CODE}` with
`from_end_time` 12 months back (from today), `api=0`, `limit=1`. `filtered` 0 →
**Exit: no data** (below). Manual runs exist → continue, whatever `api=0` says: results
marked through MCP are API results in a manual run.

### 0.2 Ask once, before collecting data

Only after 0.1 passes. Ask in one message, for the inputs the user hasn't already given.
Show what the project offers so the scope answer is easy: its test plans and milestones
with manual runs
(`SELECT (plan, milestone, COUNT(id)) entity = "run" and project = "CODE" and isAutotest
= false and started >= now("-365d") GROUP BY plan, milestone`). The `null`/`null` row is
manual runs with neither: say how many there are, with a few titles, so the user can
pick a title pattern.

```
Before I start on <PROJECT>, four questions — answer what you know, skip the rest:

1. Which manual runs are regression? A test plan, a milestone, a run tag, a title
   pattern — or all manual runs. Seen in the last 12 months: <plans / milestones>.
2. Roughly how many hours does it take your team to write one automated test:
   e2e (UI) / API / unit?
3. About how much of that effort goes into keeping a test working per year (%)?
4. Can your automated tests already read emails, receive SMS/OTP codes, pay in a
   payment sandbox (including 3DS), and run on mobile devices? Tests that need one of
   these and can't yet are listed separately, with what the missing piece would unlock.
```

Then continue with what you have:

- No scope → all manual runs, cycles grouped by ticket key (1.5). Say so in the header.
- With a scope, say in data notes how many manual runs and results in the window fall
  outside it: if they look like regression too, manual time is understated.
- No hours per test → **no ROI**: Stage 3 reports manual time and difficulty instead.
- Hours but no maintenance share → ROI and payback **before maintenance**, labelled.
- No harness answer → treat a dependency as having no harness, and say so in its reason.
  If the case itself names a sandbox or test tool ("provider sandbox with 3DS test
  card"), add that it may already exist and one answer would move the test to Automate
  now.

### 0.3 Choose the data path

Run the **mode probe** from `references/data-sources.md` once:

- rows → **QQL mode**
- `too complex` or a permission/plan error → **REST mode**. Don't retry other QQL
  result queries: when the result index is too large, every one of them fails the
  same way, however narrow.
- zero rows → the 90-day window is empty: widen it (1.5), don't switch modes.

Say which mode you used in the report. QQL on `case` and `run` works in both modes.

## Stage 1 — Demand

### 1.1 Collect manual executions in the window

**Scope first.** With a scope, collect only the regression runs it names: QQL `run` with
`plan = "<title>"`, `milestone = "<title>"`, `tags in ["<tag>"]` or `title ~ "<pattern>"`,
plus `isAutotest = false`. In QQL mode filter results by `runId in (...)` for those runs
(150 per query).

**QQL mode:** page the compact result-row query from the reference (with the scope's
`runId in (...)`). It carries `runId`, `author`, `ended`, `caseId`, `status` — enough
for counts, the counting rules below and working time (1.4). Only when the window holds
more than 10,000 rows (QQL's cap) rank first with the per-case aggregate query, then
page compact rows for the runs the shortlist appears in.

**REST mode:** MCP output lands in your context, so don't page every result. Measure
**frequency from run case lists**, and working time from the manual results of the
scope runs (1.4):

1. Manual runs in the window: QQL `entity = "run" and project = "CODE" and isAutotest =
   false and started >= now("-90d")` (plus the scope filter), paged. Drop runs whose
   stats show every case untested.
2. Their cases: `GET /v1/run/{CODE}/{id}` with `include=cases` per run, or page
   `GET /v1/run/{CODE}` with `include=cases` and `from_start_time` (unix) when there are
   many, keeping only the manual run IDs.
3. Executions per case = number of runs it appears in (distinct per run).

State in the report that frequency came from run case lists: counted per run, untested
assignments included, parameter rows added in 2.1.

If a REST call times out, move the window start by a day and retry once; if it fails
again, rely on the QQL run data and say so.

Do the arithmetic (intervals, medians, `H`) in a script, never in your head. If the
client saved a tool result to a file, read that file; otherwise write each page's JSON
to a scratch file exactly as returned and parse it.

Counting rules for result rows:

- Drop `untested`, `skipped`, `in_progress`, `invalid`, `deleted` — no completed work.
- Drop `retest` — a status reset, not an execution.
- Drop **re-marks**: a result of the same case in the same run, under 15 s, ending within
  2 minutes after a `retest`. A later pass is an execution.
- Keep several results of one case in one run when no retest sits between them — those
  are **parameter rows**, each a real execution.
- Keep workspace custom statuses.

### 1.2 Keep only tests a human still runs

Join the executed case IDs against cases with the QQL `case` query from the reference
(150 IDs per batch). Keep `automation` 0 (Manual) and 1 (To be automated). This also
returns `title`, `priority`, `severity`, `layer`, `suite`.

### 1.3 Merge clones into logical tests

Teams often clone a regression suite for every cycle, so the same check gets a new case
ID each time and per-ID frequency hides the repetition. Find repeated titles in one
call with the clone query from the reference (`GROUP BY title HAVING COUNT(id) > 1`).

A **logical test** is a set of cases with the same normalised title (lower-case,
trimmed, leading `CODE-123.` stripped) that are really one check. Generic titles
("Delete", "Sign up", "Check in the dark theme", "Installation of the integration")
recur for different screens and integrations, so merge two cases only when:

- their suites have the same title, **or**
- they belong to a cloned block: their two suites share at least five titles.

Sum a logical test's executions and keep its case IDs; use the most recently updated
case as its representative (on a tie, the highest ID — the newest clone). In 2.1,
confirm each shortlisted merge: the representative and one other clone must have the
same leaf-step count and first step; otherwise split.

If clones exist, it is a finding: report how many logical tests span how many case IDs,
and that running one canonical suite would make this measurable. Count only executed
case IDs in the header; name clones with no executions in scope in data notes. A
clone's executions outside the scope don't count. Report a clone family even when only
one of its copies ran in scope.

### 1.4 Working time `t` per execution

Recorded `time_spent` is mostly the status-click timer (seconds) or a timer left running
(hours). Measure the tester's **working time** instead: in a run, a tester marks cases
one after another, so the gap between two consecutive results is the time spent on the
second one.

For each run and author, sort the counted executions by `ended`:

- **Interval** = `ended` minus the previous execution's `ended` by the same author in the
  same run.
- The first execution in a run measures from the run's `started` (QQL `run`), but only
  if the tester is the run's only author.
- A gap longer than the **idle cutoff** (30 min) is a break, not work: the execution
  that ends it has no interval.
- Several executions ending in the same second were submitted together: split the
  interval before them evenly among them.
- An interval longer than the duration cap (4 h) is discarded.

Per logical test, `t` is chosen in this order, and the source is shown in the report:

1. **interval** — median of its intervals (mark "low sample" under 3);
2. **project median** — median of all intervals in the project, labelled estimated.
   A test that always follows a break never gets an interval of its own; name such
   tests in data notes. Don't read a gap that repeats every cycle as work: a lunch
   break repeats too.

Recorded `time_spent` is never `t` while the project has intervals: it is the UI timer.
Use it (median of values between 15 s and the cap, labelled "recorded") only when the
project has no intervals at all.

If the idle cutoff removes a third or more of one test's intervals, the test may be long
rather than interrupted: recompute its intervals with the cutoff raised to 60 min and
show both; that test's `H` uses the 60-min value. The project median and interval
coverage stay at 30 min. If it still has none, it takes the project median like any test without an
interval.

Data source: QQL compact result rows in QQL mode. In REST mode, the manual results of
the scope runs: `GET /v1/result/{CODE}` with `run` = the manual run IDs, no `api` filter, paged
(`run_id`, `author_uuid`, `end_time`). Intervals need every result of a run, not only
the shortlisted cases.

**Cycle time:** per run, the time from its first to its last manual result; report the
median across runs. It is the wall-clock cost of one regression, which a release
manager reads more easily than hours a year.

Report working time per test: how many tests (and their executions) got `t` from
interval, project median, or recorded. Report the **interval coverage** too (share of
executions with an interval). Under 30%, say so up front: results are posted in batches
after the work, so the ranking rests mainly on frequency, and the team should mark
cases as they test them.

### 1.5 Check the window shows recurring work

With a scope from 0.2, every run in it is one regression cycle — skip the ticket-key
grouping below.

Without a scope, count recurrence in **cycles**, not runs: runs whose titles carry the
same ticket key (`[GTM-166]`, `APPS-1989`) are one cycle — "Final Check" and "Final
Final Check" of one feature are not a regression cycle. Say in the header that cycles
were inferred from run titles.

A test is **one-off** if it appears in one cycle.

- Empty window → widen to 6, then 12 months (QQL: rerun the probe; REST: the run query).
- If **70% or more** of executed logical tests are one-off, the window is showing
  feature acceptance, not regression. Widen once to 12 months and state both shapes
  ("in 90 days 100% of tests were one-off; over 12 months 95%").
- Still 70% or more one-off at 12 months → **Exit: no recurring manual work**.

### 1.6 Rank, shortlist, verify

Manual hours per year:

- tests seen in **two or more cycles**: `H = executions × t × (365 / window_days)`;
- **one-off** tests: `H = executions × t` (once a year at most — a single cycle is no
  evidence of repetition).

`t` in hours.

Sort by `H`, compute cumulative share, and shortlist the logical tests covering 80% of
manual time — including the test that crosses 80% — at most 50. Report the Pareto shape
("12% of manual tests take 80% of manual time") — often the headline by itself.

Verify the shortlist through REST in both modes: `GET /v1/result/{CODE}` with the
shortlist's `case_id` list, `from_end_time`, the scope's run IDs in `run` (when a scope
is set), **no `api` filter**:

A result is **manual work** when it was marked in the UI (`is_api_result: false`) **or**
it sits in a manual run (`isAutotest = false`): a team that marks cases through an MCP
client or a script posts manual results through the API. An API result in an automated
run (`isAutotest = true`) is a reporter's.

- Recompute executions from manual-work results with the 1.1 rules — in REST mode this
  replaces the run-case-list counts, which include untested assignments. Counts are
  enough: read `filtered` with `limit=1` per split (scope runs vs automated runs)
  rather than paging rows. If the total for the shortlist matches the count from 1.1,
  the per-test counts stand; otherwise split the list in halves until it matches, and
  page the rows of a mismatched test to apply the status rules (`filtered` counts
  every status). `t` stays from 1.4: an interval needs the neighbouring results, which
  a `case_id` filter doesn't return.
- A test with **no** manual-work results left was not run by a person: drop it, then
  backfill the shortlist from the ranked list until it covers 80% again. Verify
  backfilled tests the same way.
- A reporter's results on a Manual case are not proof it is automated. List each such
  test under **API results on manual cases** (count, and the runs most of them came
  from); never call it automated.

List any case you couldn't check.

## Stage 2 — Feasibility

### 2.1 Read each shortlisted test

`qase_get` the whole representative case of **every** shortlisted test (no `fields`
projection). A case without steps has no `steps` key — that is a title-only case. Shared
steps arrive inline; count leaf steps, nested steps included. Parameter rows = product
of `params` value-list lengths.

Results already count parameter rows separately, so after 1.6 no multiplication is
needed; if a test's executions still come from run case lists only, multiply by its row
count and recompute `H`. If a parameterised test has one result per run, the tester
marked all rows at once: its interval already covers them, so don't multiply; say so.

A test you could not read can't be classified: leave it out of the ranking and list it
under data notes. A title-only case can't be "Automate now": it is "Fix case first" or
"Keep manual".

### 2.2 How to automate: layer and test count

Decide for each test **what it checks**, then the cheapest layer that checks it. A
manual case describes a user's path; the automated version need not follow the path.

| What the steps check | Automate as |
|---|---|
| A user journey across screens: the flow itself is the point | 1 e2e |
| Business rules through a form: validation, calculations, limits, statuses | API tests, one per rule group; plus 1 e2e smoke only if the screen wiring matters |
| Pure logic shown on screen: formatting, sorting, conversion | unit tests (the dev team's); note it is outside QA automation |
| Parameter rows over the same flow | 1 data-driven test at the lowest layer that exercises the rule |
| Layout, visual look, usability | Keep manual |

Count tests the way an automation engineer would:

- Data rows for the same rule (a valid and an expired code, three roles) are **one**
  data-driven test. A new test only for a different rule or a different setup.
- When the expected result is data or state (a total, a saved record, access
  denied), the API test is enough. Choose e2e only when the expected result is what
  the screen does (navigation, rendering, layout).
Then write two variants, so the choice is a rule and not a judgement:

- **Full** — every objective expected result in the case, each at the layer the rules
  above give.
- **Lean** — the fewest, lowest-layer tests that assert the case's main claim (what its
  title promises: "Logout clears the session" → the session is rejected after logout).
  Name what Lean **gives up** from Full ("the browser Back cache check in step 3").
  What Lean gives up a tester still checks by hand, so Lean saves less: its `a` is the
  share of the case's leaf steps it asserts (times Full's `a` if the case is Partially
  automate).

When both are the same, write one. Stage 3 picks between them by ROI. Class goes with
the variant: if only Full asserts through a missing harness, Lean can still be
Automate now.

Read the case's `layer` field first. If it is set and you recommend another layer, say
why in the reason ("layer E2E, but steps 3–9 check discount rules — 2 API tests + 1 e2e
smoke"). If it is not set, the recommendation stands on the steps alone.

Write each variant as `1 e2e`, `3 API`, `2 API + 1 e2e`.

### 2.3 Score difficulty and classify

Score 1 (easy) to 3 (hard), at the recommended layer:

| Dimension | 1 | 3 |
|---|---|---|
| Step clarity | Every step has an action and an expected result | Vague steps, missing expected results, no steps |
| Verifiability | Objective assertions (value, status code, element state) | Subjective (looks right, feels fast) |
| Data and setup | Explicit data or parameters, simple setup | Production-like data, manual seeding, special accounts |
| External dependencies | None, or one the team has a harness for | Email/SMS/OTP, captcha, payment, hardware without a harness |
| Interface | API or stable web UI | Native mobile, desktop, canvas, multi-device |
| Size and flow | Up to 10 steps, linear | 25+ steps, branching, long or time-based waits |
| Stability | Unchanged for months, or no history yet | Updated often in the last 6 months, or flagged flaky |

**Difficulty** (for the variant chosen): **Hard** if any dimension scores 3, **Medium**
if two or more score 2, otherwise **Easy**. A title-only case gets no score ("—"). Name
the dimensions that set it ("Medium: 22 steps; production-like data"); for a blocked test write
"Easy, blocked by SMS/OTP harness" so the blocker is not lost in the grade.

A dependency used only for setup (a paid order to start from) is not blocking: seed it
as a fixture, and score it under Data and setup. It blocks only when the test asserts
through it (reads the SMS code, completes the 3DS challenge).

Class and automatable fraction `a`:

| Class | When | `a` |
|---|---|---|
| Automate now | Clear, verifiable, no blocking dependency | 1.0 |
| Fix case first | Worth it, but the text has gaps — list the edits that unlock it | 1.0 once fixed |
| Partially automate | Some steps need a human (visual check, physical device) | share of leaf steps with objective assertions, at most 0.7 (a person still sets up and does the manual step) and at least 0.3 |
| Needs a harness | Depends on email, SMS/OTP, payment or devices the team has no harness for | 1.0 once the harness exists |
| Keep manual | Exploratory, usability, subjective | 0 |

Each test gets a **one-line reason that cites a specific step or field**: "12 clear
steps, card data in step 4, rules checked in steps 5–9 — 2 API + 1 e2e, Easy"; "step 7
reads an OTP from SMS, no harness — Needs a harness"; "title-only, no steps — Fix case
first".

### 2.4 Order of importance

Teams automate critical paths first, and tests that catch bugs. Count each test's
**fails** in the window (failed and blocked results, from the compact rows) and show
them; a test that fails is earning its keep.

Put a test in the **Critical** band when its
priority is High or its severity is Blocker or Critical (numbers in the reference;
custom options by name from `/v1/system_field`); everything else is **Standard**. Every ranked list below shows
Critical first, then Standard, and states this in the header. If the user asks for pure
savings order, drop the bands.

## Stage 3 — ROI (only with the team's hours per test)

Effort per test, from the user's figures only:

```
E = Σ over layers (tests at that layer × team's hours per test at that layer)
```

A layer the user gave no hours for → that test has no `E`: show it with its difficulty,
outside the ROI table. A Hard test is likely above the team's typical figure: say so in
its reason; don't multiply. A "Needs a harness" test gets no `E` until the harness
exists: list it with the harness it waits for and the tests it would unlock.

Per logical test, 12-month horizon, for each variant:

```
S       = H × a                    manual hours saved per year
M       = E × m                    maintenance per year; m = the team's share
ROI     = (S − M) / E              hours returned per hour invested, year one
Payback = E / ((S − M) / 12)       months; "never" if S ≤ M
```

Without a maintenance share: `M = 0`, and label every ROI and payback "before
maintenance".

**Pick the variant:** Full if its ROI ≥ 1; else Lean if its ROI ≥ 1, with what it gives
up in the reason; else Full, which goes to Not worth automating yet with Lean's ROI
beside it. Fixed rule, same answer on every run.

**Break-even:** per test, the hours per test at its layer below which it still pays back
in year one: `S / ((1 + m) × tests in the variant)`. "Pays back while an API test costs
≤ 3.7 h" tells the team how much the verdict rests on their estimate.

Within each band, rank by ROI; at ROI within 10% of each other, more fails first. Tests with ROI < 1 go to **Not worth automating yet**
with the reason (runs rarely, subjective, Hard at a layer the team prices high) — as
useful to a QA lead as the top list.

**Portfolio:** walk every test with an `E` (ROI < 1 included) in ROI order, bands
ignored, and accumulate effort and savings; show rows for the
top 10, 25 and 50 (or as many as exist).

**Budget:** take tests in ranked order (ROI ≥ 1 only), skipping any that no longer fit,
until the budget is spent. Report the set, total effort, hours saved per year, the share
of manual time it removes, the minutes it takes off each regression cycle (Σ `t × a`
of the set), and the set's payback: `ΣE / ((ΣS − ΣM) / 12)` months. If budget is left when the shortlist runs out, classify
the next tests in the ranked list (beyond 80%, up to 50 in all) and keep filling; then
name what the rest could buy instead (a harness, the case fixes). If no test reaches
ROI ≥ 1, allocate nothing and say so
in the headline; show what the best set would return anyway, labelled as not paying
back on hours, so the user can decide on risk grounds.

**Without hours per test**, skip ROI, portfolio and budget. Rank by band, then by `H`,
and show each test's How, Difficulty and reason. Headline: where the manual time goes,
and which of those tests are Easy. End with: "Give me your hours for one e2e, API and
unit test and I'll add effort, ROI and payback."

Name, don't count, the upside hours miss: an automated test can run on every commit
instead of every release.

## Exits — report these instead of a ranking

**Exit: no data** (from 0.1). Two or three sentences, nothing else. For the last manual
run, rerun the 0.1 run query without the date filter.

```
<PROJECT> has no manual test results in the last 12 months (last manual run:
<date>, or "none"), so there is no manual QA time to analyse. If manual testing
moved to another project, run this there; if you know which areas will be tested
by hand and how often, tell me and I'll rank them.
```

Add one sentence only if it applies: "It has <n> cases marked To be automated; I can
size and order them by priority instead." or, for a project with no cases, "The project
has no test cases yet."

**Exit: no recurring manual work** (from 1.5). Per-test ROI is meaningless when tests
don't repeat, and annualising single runs inflates them. Keep it short:

- headline: "<PROJECT> is used for one-off feature acceptance: <x>% of tests were
  one-off in 12 months; automating existing cases would not pay back";
- up to 10 tests that recurred across cycles, with their run counts;
- **recurring areas**: suites touched in three or more cycles over 12 months;
- **clone families** — the same check recreated per feature or per cycle: candidates for
  a small canonical regression suite, which is where automation would start paying;
- one question: which of these areas will be re-tested in coming releases, and how
  often? Their answer is the frequency the data can't give.

Allocate no budget. Skip Stages 2–3 unless the user names areas and a frequency; then
run them on those areas with that frequency.

## Report

Lead with the answer, then the evidence, then the actions.

Write the report in English, whatever language the user asked in.

```
## Automation candidates — <PROJECT>
_Generated by Qase Quality Supervisor · prioritizing-automation-candidates skill_

Window: <from> – <to> (<n> days)<, widened from 90 because …> | Data path: <QQL | REST>, <n> calls in all
Scope: <plan / milestone / tag / pattern | all manual runs, cycles inferred from run titles>
Manual executions: <n> across <k> logical tests (<c> executed case IDs) of <N> manual cases (Manual + To be automated)
Manual time: <h> h in window, <h> h/year annualised
Working time: <x>% of executions have an interval; t from interval for <a> tests (60-min recompute included), project median for <b>, recorded for <c>
Cycle time: <median h per regression run>
Effort basis: <team: e2e X h, API Y h, unit Z h; maintenance m% | not given — no ROI>
Order: Critical band (High priority or Blocker/Critical severity) first, then by <ROI | manual h/yr>

### Headline
<"25 tests take 49% of manual QA time. Automating them as 31 API and 9 e2e tests costs
about 170 h at your rates and saves about 790 h a year; payback under 3 months.">

### Top candidates
| # | Band | Test | Case IDs | Runs | Fails | Typical time | Manual h/yr | How | Difficulty | Class | Effort h | Saved h/yr | ROI | Payback | Break-even |
Reason: <one line citing a step or field; Full or Lean, and what Lean gives up>
(Without hours per test: drop Effort, Saved, ROI, Payback and Break-even; show both variants.)

### Fix case first
<test — what is missing — the edits that unlock it>
### Needs a harness
<harness — the tests it would unlock — their manual h/yr>
### Not worth automating yet
<test — reason; Keep manual tests here too>
### Budget plan        (only with a budget and hours per test)
### Portfolio          (only with hours per test)
### API results on manual cases
<test — API results / human results in window — main runs; "API results also come
from MCP, scripts and importers: check before relabelling">
### Data notes and caveats
<clones; estimated times; low samples; truncation>
### Queries used
<every QQL query and REST call, verbatim>

---
_Generated by Qase Quality Supervisor · prioritizing-automation-candidates skill_
```

State every denominator. If anything was truncated or sampled, say what and how much.
Offer the full ranked list as CSV.

## Write back — only after explicit approval

One offer, with its case list and its own yes: mark the selected candidates "To be
automated" and tag them (for example `qs-automation-candidate-2026Q4`) so a re-run in
90 days can measure realised savings. For a logical test, ask whether to mark every
clone or only the representative.

Then `qase_case_upsert` per case with `automation` and `tags`; read the case's current
tags first and send them along, so none are lost.

Never set a case to "Automated": API results don't prove a reporter runs it.

## Guardrails

- Analysis is read-only. `qase_api` with `GET` only.
- Write only "To be automated" and tags, only on approved cases. Never delete.
- Never invent effort hours or a maintenance share. Use the team's, or show no ROI.
- An empty window or a missing QQL plan is "no data", never "no candidates".
- Never count `retest` or re-marks as executions; always count parameter rows.
- State window, scope, data path, effort basis and working-time sources in every report.

## Not in this version

Generating automation code; reading the automation repository; dollar ROI without a
supplied rate; cross-project ranking.
