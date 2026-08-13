# QQL reference

Field names, enum values, and limits for Qase Query Language, as used by the
Quality Supervisor skills. Every statement here was verified by running the
query against a live Qase workspace — where the official docs and live
behaviour disagree, live behaviour is what is documented below.

Read this before composing any query. Field names are **not** uniform across
entities, and the wrong name returns `Qase Query error: unavailable attribute`
rather than an empty result — a hard failure, not a silent one.

**QQL requires a Business or Enterprise subscription.** On lower plans
`qql_search` fails for every query. If it fails with a permission error, say so
plainly and stop rather than retrying variations.

## Query forms

**Filtering:**

```
entity = "case" and project = "DEMO" and priority = "High" ORDER BY created DESC
```

**Aggregating** — note the parentheses around the SELECT list. Without them the
query is rejected with `Query is invalid`:

```
SELECT (status, COUNT(*)) entity = "result" and project = "DEMO" GROUP BY status
```

Rules: `SELECT (...)` first, then conditions, then `GROUP BY`, then `HAVING`.
One line only, no newlines. No `WHERE`/`LIMIT`/`OFFSET` keywords. One `ORDER BY`
field maximum. Every non-aggregated field in `SELECT` must also appear in
`GROUP BY`.

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
**There is no field linking a requirement to its test cases**, so
requirement→case coverage cannot be computed in QQL at all; it needs the REST
API via `qase_api`.

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
| `automation` | Manual, To be automated, Automated (`"Not automated"` is accepted as an alias for Manual) |
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

Codes 1, 2, 5, 8 for `result.status` and all three `automation` codes were
confirmed live; the rest follow the documented option order — state the label
you inferred rather than presenting an unverified mapping as fact.

## Limits

| Constraint | Value |
|---|---|
| rows per call | 100 maximum (a higher `limit` is rejected outright) |
| default rows | 10 — via `qql_search`, if you omit `limit` you get 10 |
| total matchable rows | 10,000 |
| maximum offset | 100,000 |
| query length | 1,000 characters through MCP (2,000 via REST) |
| rate limit | 1,000 requests/minute per token |

`qql_search` returns `total` next to `entities`. **Always compare the two.**
If `total` exceeds the rows you received, you are looking at a page, not the
answer: either paginate deliberately, narrow the query, or state the sample
size in the report. Never present a page as a project-wide figure.

A list of IDs in a query is bounded by the 1,000-character limit — roughly 80
integer IDs plus surrounding clauses. Batch larger sets.

## Aggregates available outside QQL

Some numbers are cheaper or only available through REST (`qase_api`):

- `GET /v1/suite/{code}` returns `cases_count` per suite — empty and thin
  suites without a query per suite. Paginate: `limit` 100.
- Run entities carry `stats.statuses` (counts per status), `time_spent`, and
  `elapsed_time` — a run's pass rate without fetching a single result row.
- `GET /v1/system_field` returns the workspace's real enum options.
