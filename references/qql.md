# QQL reference

Field names, enum values, and limits for Qase Query Language, as used by the
Quality Supervisor skills. Every statement here was verified by running the
query against a live Qase workspace — where the official docs and live
behaviour disagree, live behaviour is what is documented below.

Read this before composing any query. Field names are **not** uniform across
entities, and the wrong name returns `Qase Query error: unavailable attribute`
rather than an empty result — a hard failure, not a silent one.

MCP server 2.1.1 documents much of this in `qql_help` too — field names per
entity, the aggregation syntax, and the enum-to-integer mapping. Consult either;
where they differ, this file is the one that was executed against a live
workspace.

What `qql_help` cannot tell you is where QQL disagrees with the REST API about
the data itself. That is the last section here, and it still applies.

## Contents

- **Query forms** — filtering and aggregating; the two rules that make `SELECT` work
- **Timestamp fields** — the names differ per entity, and guessing wrong is a hard error
- **Fields per entity** — case, run, result, defect, plan, requirement
- **Field quirks that produce hard errors** — suite titles vs IDs, no run-ID on results
- **Enum values** — the real options, and the ones that don't exist
- **Enum integers in aggregated responses** — aggregates return codes, not labels
- **Limits** — 100 rows per call, 10,000 matchable, 2,000-character queries
- **QQL and REST disagree — and not in one direction** — which source to trust per
  entity; **read this before reporting a defect count**
- **Aggregates available outside QQL** — cheaper numbers from REST

Read the section you need; the whole file is not required for a single query.

**QQL requires a Business or Enterprise subscription.** On lower plans
`qql_search` fails for every query. If it fails with a permission error, say so
plainly and stop rather than retrying variations.

## Query forms

**Filtering:**

```
entity = "case" and project = "DEMO" and priority = "High" ORDER BY created DESC
```

**Aggregating** — two things have to be right or the query is rejected outright
with `Query is invalid`, which tells you nothing about which one is wrong:

1. the SELECT list is wrapped in **parentheses**
2. `SELECT (...)` comes **first**, before the conditions

```
SELECT (status, COUNT(*)) entity = "result" and project = "DEMO" GROUP BY status
```

Then conditions, then `GROUP BY`, then `HAVING`. One line only, no newlines. No
`WHERE`/`LIMIT`/`OFFSET` keywords. One `ORDER BY` field maximum. Every
non-aggregated field in `SELECT` must also appear in `GROUP BY`.

Aggregates: `COUNT(*)`, `COUNT(field)`, `MIN`, `MAX`, `AVG`, `SUM`, `FIRST`,
`LAST`. `tags` cannot be grouped or aggregated on `case`, `run`, or `defect`
(it can on `result`); `defect.isResolved` and `result.isEnded`/`isDeleted`
cannot be aggregated.

**Prefer aggregation over pagination.** A `GROUP BY` returns the whole
distribution in one call; fetching rows to count them yourself needs one call
per 100 rows and will silently under-count (see Limits).

## Timestamp fields — names differ per entity

| Entity | Timestamp fields |
|---|---|
| `case` | `created`, `updated`, `deleted` |
| `defect` | `created`, `updated`, `resolved`, `deleted` |
| `plan` | `created`, `updated`, `deleted` |
| `requirement` | `created`, `updated`, `deleted` |
| `run` | `started`, `ended` — **no `created`/`updated`** |
| `result` | `ended` — **only this one** |

Rejected (confirmed): `result.created`, `result.time_created`,
`result.end_time`, `run.created`, `run.updated`, `run.start_time`,
`case.created_at`. `ORDER BY started DESC` / `ORDER BY ended DESC` work, and
ordering runs by `started` is how you find the most recent run — there is no
`created` to sort on.

Time functions: `now("-30d")` (`d`/`w`/`m` offsets), `startOfDay`, `endOfDay`,
`startOfWeek`, `endOfWeek`, `startOfMonth`, `endOfMonth`.

## Fields per entity

**`case`** — `id`, `title`, `description`, `preconditions`, `postconditions`,
`status`, `type`, `behavior`, `automation`, `isManual`, `isToBeAutomated`,
`priority`, `severity`, `layer`, `isMuted`, `isFlaky`, `isAiGenerated`,
`suite`, `suiteTree`, `milestone`, `tags`, `project`, `author`, `createdBy`,
`updatedBy`, `created`, `updated`, `deleted`, `isDeleted`, `cf["…"]`.

**`run`** — `id`, `title`, `description`, `status`, `plan`, `environment`,
`milestone`, `started`, `ended`, `isStarted`, `isEnded`, `isPublic`,
`isAutotest`, `isScheduledRun`, `hash`, `type`, `tags`, `project`, `author`,
`createdBy`, `deleted`, `isDeleted`, `cf["…"]`.

**`result`** — `id`, `caseId`, `case` (case title), `run` (run title),
`status`, `priority`, `severity`, `type`, `layer`, `suite`, `tags`, `comment`,
`timeSpent`, `ended`, `isEnded`, `deleted`, `isDeleted`, `milestone`,
`project`, `author`, `createdBy`, `assignee`.
`priority`/`severity`/`type`/`layer`/`tags` are inherited from the case, so you
can filter results by case attributes in a single query — no join needed.

**`defect`** — `id`, `title`, `actual_result`, `status`, `severity`,
`resolved`, `isResolved`, `milestone`, `tags`, `project`, `author`,
`createdBy`, `created`, `updated`, `deleted`, `isDeleted`, `assignee`,
`cf["…"]`.

**`plan`** — `id`, `title`, `description`, `project`, `created`, `updated`,
`deleted`, `isDeleted`. Nothing else: no status, no milestone. To scope by plan,
query runs with `plan = "…"`.

**`requirement`** — `id`, `title`, `description`, `parent`, `status`, `type`,
`project`, `author`, `createdBy`, `created`, `updated`, `deleted`, `isDeleted`.
Queryable and groupable like any other entity, and the response carries
`parent_id`, so the epic → user story → feature hierarchy is available.

**But there is no field linking a requirement to its test cases**, in either
direction — not on `requirement`, not on `case`, and not in either response
shape (`RequirementQuery` returns only the fields above; `TestCaseQuery` has no
requirement field). `qase_get` does not support requirements and the REST API
has no requirements endpoint, so there is no fallback: **requirement→case
coverage cannot be obtained at all.** Report it as unavailable rather than
substituting another measure.

Requirement `status` and `type` are the only genuinely case-sensitive enum values
in QQL, and they are also the one place where filter values and response values
differ: filter with the label (`type = "User story"`), but the response returns a
slug (`user-story`). Unlike everything else in this file, the case-sensitivity
part comes from the official field reference rather than a live check — the
workspace used for verification had no requirements, and on an empty set a
rejected value and a value that simply matches nothing look identical. Use the
documented casing.

## Field quirks that produce hard errors

- `case.suite` is a **title string**. `and suite = 1` fails with
  `invalid value: 1`. `result.suite` is a **suite ID integer**.
- `case.suiteTree` matches a suite **and all of its descendants** — use it for
  "everything under area X" instead of enumerating child suites.
- `result` has **no `environment` and no `configuration`**. "Flaky only on
  staging" cannot be answered from result rows; go through `run.environment`
  and the runs in that environment, or say the data isn't reachable.
- Grouping on a string field returns it with a `_title` suffix: `GROUP BY suite`
  yields `suite_title` in the response.

## Enum values

Enum options are **workspace configuration** — an admin can change them, and
they are not exposed by any core tool. `GET /v1/system_field` via `qase_api`
returns the workspace's real options. The values below are the defaults;
verify before relying on an unusual one, and never invent a value.

| Field | Values |
|---|---|
| `priority` | Not set, High, Medium, Low — **there is no "critical"** |
| `severity` | Not set, Blocker, Critical, Major, Normal, Minor, Trivial |
| `case.status` | Actual, Draft, Deprecated |
| `automation` | Manual, To be automated, Automated (`"Not automated"` is accepted as an alias for Manual) — the filter works, but **the value it filters on can lag the live case**; see the warning below |
| `layer` | Not set, E2E, API, Unit |
| `type` | Other, Functional, Smoke, Regression, Security, Usability, Performance, Acceptance, Compatibility, Integration, Exploratory |
| `run.status` | In Progress, Passed, Aborted, Failed — `"active"` is **not** valid |
| `defect.status` | Open, In progress, Resolved, Invalid |
| `result.status` | Passed, Failed, Blocked, Retest, Skipped, Deleted, In progress, Invalid — **excludes Untested** |
| `requirement.status` | Valid, Draft, Review, Rework, Finish, Implemented, Not testable, Obsolete (case-sensitive) |
| `requirement.type` | Epic, User story, Feature (case-sensitive) |

Because `result.status` has no `Untested`, **cases that were never executed
cannot be found by querying results.** Compare the case list against cases that
do have results, or use run statistics.

Values are matched case-insensitively in practice for most enums, but
`requirement.status` and `requirement.type` are genuinely case-sensitive. Use
the documented casing everywhere and don't depend on the leniency.

## Enum integers in aggregated responses

Filtering takes labels (`status = "failed"`), but a `GROUP BY` returns the enum
as an **integer**. Map them back before reporting:

- `result.status`: 1 = Passed, 2 = Failed, 3 = Blocked, 4 = Retest,
  5 = Skipped, 7 = In progress, 8 = Invalid
- `case.automation`: 0 = Manual, 1 = To be automated, 2 = Automated
- `case.priority`: 0 = Not set, 1 = High, 2 = Medium, 3 = Low

### QQL reads its own index, which lags the live case

The filters work. What they filter is a separate index that catches up
asynchronously, so a query can be internally consistent and still describe the
project as it was minutes — sometimes far longer — ago.

Measured on 2026-08-21 against a purpose-built project with known contents
(9 cases, created through the API):

| Event | When QQL reflected it |
|---|---|
| New project + 8 cases created | invisible for ~3 min; **partial** at 3 min (1 of 8, reported as a clean `COUNT(*)` of 1); converged at 5–7 min |
| One case's `automation` and title changed | still stale at 10 min; correct by ~17 min |

The partial state is the dangerous one: `COUNT(*)` returned `1` with nothing in the
response to say the other seven cases were still in flight.

**Staleness can be much worse than minutes.** On one large, long-lived project, two
cases read `automation: 2` (Automated) through REST — and had for eleven days — while
QQL still reported `0` (Manual). A plausible cause is a
stalled analytics republish for that project (the failure mode that branch
`NSGHTS-155` fixes: the catch-up times out, retries the same statement, and parks as
permanently failed with no automatic recovery). Treat a long-lived divergence as a
signal that a project's republish is stuck, not as normal latency.

**A full-entity response mixes both sources**, which makes this confusing to diagnose.
Ask for whole cases and the hydrated fields show live values; ask for a projection —
`SELECT (id, automation) …` — and the same case reports the index's values. One query,
two answers, with the predicate agreeing with the projection.

**So:** for a decision that turns on a single case — "does a human still have to run
this?" — take the value from the full entity or confirm with `qase_get`. For a reported
figure, say it came from QQL, and spot-check a few rows against REST when the number
matters. Right after a write, do not trust a QQL count at all: wait, or read through
REST.

### `isManual` and `isToBeAutomated` do not mean what REST means by them

Verified on the same clean project. REST sets `isManual: true` for `automation` **0 and
1** — "not automated, a human still runs it". QQL's flag of the same name selects
`automation = 1` only, and `isToBeAutomated` returns exactly the same rows:

| Query on the clean project | Returned | Ground truth |
|---|---|---|
| `isManual = true` | 2 cases, both `automation: 1` | 5 cases have REST's `isManual` (three `0`, two `1`) |
| `isToBeAutomated = true` | the same 2 cases | 2 ✓ |

In QQL the two flags are aliases for *To be automated*. Do not use either to mean
"not automated" — filter on `automation` and read the field.

### A title can name more than one suite

`case.suite` matches by title, and a project may hold several suites sharing a name.
Two suites deliberately titled `Collide` in the clean project, holding one case each,
were returned as one group by `suite = "Collide"`; on a real project the same shape
returned 11 cases where the suite of that name in the tree held 6. A count scoped that
way is not scoped to the suite you meant. Confirm with
`SELECT (suite, COUNT(*)) … GROUP BY suite`, or scope by id where you can.

### Two things that looked broken and are not

Worth recording because both cost real time, and both were properties of one messy
project rather than of QQL:

- **Combining an `automation` predicate with another filter is fine.** On the clean
  project `suite = "Collide" and automation = "Manual"` returned exactly the one
  matching case, and `automation = "Manual" and id in [1..5]` returned exactly two.
- **Row duplication is data-dependent, not general.** On one real project a
  five-element `id` list came back as eight rows with three cases repeated; the same
  shape of query on clean data returned no duplicates. Those cases carried repeated
  custom-field entries, which is the likely fan-out. Still worth deduplicating by id before counting
  from a row query in an unfamiliar project — and aggregation avoids the question
  entirely: `GROUP BY` summed exactly to an independent `COUNT(*)` everywhere it was
  checked.
## Limits

| Constraint | Value |
|---|---|
| rows per call | 100 maximum (a higher `limit` is rejected outright) |
| default rows | 10 — via `qql_search`, if you omit `limit` you get 10 |
| total matchable rows | 10,000 |
| maximum offset | 100,000 |
| query length | 2,000 characters (raised from 1,000 in MCP server 2.1.0) |
| rate limit | 1,000 requests/minute per token |

`qql_search` returns `total` next to `entities`. **Always compare the two.**
If `total` exceeds the rows you received, you are looking at a page, not the
answer: either paginate deliberately, narrow the query, or state the sample
size in the report. Never present a page as a project-wide figure.

A list of IDs in a query is bounded by the character limit — roughly 170 integer
IDs plus surrounding clauses at 2,000. Batch larger sets, and keep a margin:
case IDs grow as a workspace ages.

## QQL and REST disagree — and not in one direction

They are different views of the same data. Across 34 projects, 20 of 52 entity
counts differed, and **which source is higher depends on the entity**:

| Entity | Direction | Observed |
|---|---|---|
| `case` | QQL ≥ REST, slightly | 1.00–1.31× (17907 vs 17901; 4262 vs 3262) |
| `run` | QQL ≥ REST | often exactly 2.00×, up to 16×; QQL also returns runs REST answers `Run not found` for, with `isDeleted = false` |
| `result` | QQL ≫ REST | 1.5× to 164× (11141 vs 68) |
| `defect` | **QQL ≤ REST** | 0.33–0.41×, and **0 vs 3** on projects that do have defects |

**The cause is an incomplete index over historical records, not a systematic
under-count.** A controlled experiment settled this: five defects created in a
project with none, one at each severity, then queried both ways once indexed —
every count matched exactly, including each per-severity filter and the
`open blocker+critical` total. Indexing the new writes took about three minutes.

So QQL is accurate on data it has indexed. What it misses is history: on projects
with older records the gap is large and persistent — 26 of 78 defects on one, 9 of
22 on another, and **zero of three** on two more. Small or recent projects agree
exactly, which fits the same explanation.

The defect direction is still the dangerous one in practice, because a real
project has history and a missed blocker is what clears a release that should be
held. Where 17 open blocker+critical defects existed, QQL returned 9; where three
existed, it returned none.

**So don't treat either source as canonical.** Take defects from REST
(`GET /v1/defect/{code}`, paging and tallying `severity` from the rows, since
the severity filter is ignored there). Take execution counts from run `stats`.
Use QQL for what it is uniquely good at — filtering and aggregating by field.
When a conclusion rests on a number, check it the other way and report any
disagreement instead of resolving it silently.

Representations differ too: REST returns enums as **strings** (`"blocker"`),
QQL aggregates return them as **integers**.

## Aggregates available outside QQL

Some numbers are cheaper or only available through REST (`qase_api`):

- `GET /v1/suite/{code}` returns `cases_count` per suite — empty and thin
  suites without a query per suite. Paginate: `limit` 100.
- Run entities carry `stats.statuses` (counts per status), `time_spent`, and
  `elapsed_time` — a run's pass rate without fetching a single result row.
- `GET /v1/system_field` returns the workspace's real enum options.
