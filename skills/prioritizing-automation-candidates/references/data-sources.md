# Data sources — QQL and REST, as verified

Everything here was checked against live Qase workspaces in November 2026. A wrong
field name or parameter format is a hard error, not an empty result, so copy these
forms rather than improvising.

## Contents

- Mode probe
- QQL recipes (QQL mode)
- REST recipes (both modes)
- Field semantics that are easy to get wrong
- Limits

## Mode probe

One cheap query decides the data path for the whole session:

```
SELECT (status, COUNT(id)) entity = "result" and project = "CODE" and ended >= now("-90d") and status not in ["untested", "deleted"] GROUP BY status
```

| Response | Mode | Meaning |
|---|---|---|
| rows | **QQL** | Result index is queryable |
| no rows, `total: 0` | QQL, window empty | Widen the window, don't switch modes |
| `Your query is too complex to execute` | **REST** | Workspace's result index is too large. Every result query fails this way — even `runId = 1` with no aggregation. Do not retry variants |
| permission / subscription error | **REST** | Plan below Business, no QQL |

QQL on `case` and `run` keeps working in REST mode. Only `entity = "result"` is affected.

## QQL recipes (QQL mode)

Executions and time per case — one row per executed manual case, sorted server-side:

```
SELECT (caseId, COUNT(id), SUM(timeSpent), AVG(timeSpent), MAX(timeSpent)) entity = "result" and project = "CODE" and ended >= now("-90d") and isManual = "Manual" and status not in ["untested", "retest", "skipped", "in_progress", "invalid", "deleted"] GROUP BY caseId ORDER BY sum_timespent DESC
```

- `ORDER BY` an aggregate only through its response alias (`sum_timespent`, `count_id`).
  `ORDER BY SUM(timeSpent)` is a syntax error.
- `status not in [...]` keeps workspace custom statuses (they are real executions)
  while dropping non-executions.
- 100 rows per page; page with `offset` until `total` is covered.
- Fill rate: run the same query shape with `SELECT (COUNT(id))` twice, with and without
  `and timeSpent > 0`.

Result rows, compact — what you need for working time, retests, re-marks and bulk
submissions, at a fraction of the size of REST pages:

```
SELECT (runId, author, ended, caseId, status, timeSpent, COUNT(id)) entity = "result" and project = "CODE" and ended >= now("-90d") and status not in ["untested", "deleted"] GROUP BY runId, author, ended, caseId, status, timeSpent ORDER BY runId ASC
```

Sorted by run, each row carries what the working-time intervals need (run, author,
`ended`). `author` comes back as an object (`name`, `email`); group by its email.
`count_id` above 1 means identical rows (bulk submission, same second). `status` comes
back as a number: 0 Untested, 1 Passed, 2 Failed, 3 Blocked, 4 Retest, 5 Skipped,
6 Deleted, 7 In progress, 8 Invalid; higher IDs are workspace statuses (read
`GET /v1/system_field`, `result_status`). The row carries no API flag, so it cannot
replace the REST check for API results.

## REST recipes (both modes)

### Results — `GET /v1/result/{CODE}` via `qase_api`

| Param | Format | Notes |
|---|---|---|
| `from_end_time` | `"2026-08-19 00:00:00"` | Unix timestamps and bare dates are rejected ("Data is invalid") |
| `api` | `"0"` manual / `"1"` posted through the API | `"false"` / `"true"` are rejected |
| `case_id` | `"557,558,559"` | Comma list works — verify a shortlist in a few calls |
| `run` | `"549,552"` | Comma list |
| `limit` / `offset` | max 100 / offset ≤ ~100,000 | Sorted by `end_time` ascending |

- `total` is capped (it reads 100,100 on large projects). Use `filtered` as the count.
- A `limit=1` count can time out on a project with heavy reporter traffic (seen at an
  exact 90-day boundary, fine a day later). Shift the start by a day and retry once.
- `api=1`, `limit=1` with up to 100 case IDs in `case_id` answers "were API results
  posted for any of these?" in one fast call. Read `filtered`, not rows: rows are
  30–50 KB per 100 (steps, stack traces, signed attachment URLs).
- `is_api_result: true` means the result came through the API — a reporter, but also
  an MCP client, a script or an importer. It does not prove the case is automated.
  A manual run (`isAutotest = false`) whose results are marked through MCP holds only
  `is_api_result: true` results; they are still manual work.

Collect demand by run, not by the `api` flag: pass the manual run IDs in `run`. On a
project with heavy automation one day can hold 25,000 reporter results, so never page
results without a `run` or `api` filter. `api=0` alone misses manual runs marked
through MCP or a script, whose results are all `is_api_result: true`.

Each row: `hash, run_id, case_id, status, is_api_result, time_spent_ms, end_time,
author_uuid`, optional `steps` (per-step statuses), `comment`, `attachments`.
`case_id` can be missing on reporter results that were never linked to a case.

### Runs — `GET /v1/run/{CODE}`

- `from_start_time` takes a **unix timestamp** (unlike results).
- `include=cases` adds `cases`: one entry **per result**, so a case ID repeats for
  retests and parameter rows. Count distinct IDs per run for "runs per case".
- One run: `GET /v1/run/{CODE}/{id}` with `include=cases`. The list endpoint has no
  manual/automated filter; get manual run IDs from QQL
  `entity = "run" and isAutotest = false` (works even when result QQL doesn't).
- Run case lists are the cheap frequency source: 100 runs per call versus 100 results
  per call.
- Run-level `time_spent` is the sum of every result in the run, retests and timers left
  running included. Do not use it as a sanity check for manual effort.

### Case content — `qase_get` (entity `case`)

- A case with no steps has **no `steps` key at all** (and often no `preconditions`).
  That absence is what "title-only" looks like. A `fields` projection naming `steps`
  works, but fetching the whole case is simpler and also returns `params`.
- Shared steps come back **inline**: `action`, `expected_result`, `data` and
  `attachments` filled in, with `shared_step_hash` / `shared_step_nested_hash` as
  markers. No extra call is needed.
- Nested steps: `steps[].steps[]`, any depth. Count leaf steps.
- Parameters: `params` (`{"Offset": ["0", "100000"]}`) and `parameters` (typed list).
  Row count = product of value-list lengths for single parameters; a group counts its
  rows once.
- Useful fields: `automation`, `steps_type`, `preconditions`, `postconditions`,
  `layer`, `is_flaky`, `updated_at`, `priority`, `severity`, `tags`.

### Join and metadata — QQL `case` (both modes)

```
SELECT (id, title, automation, priority, severity, layer, suite, COUNT(id)) entity = "case" and project = "CODE" and id in (101, 102, ...) GROUP BY id, title, automation, priority, severity, layer, suite
```

Clone families in one call (repeated titles with the ID span of each):

```
SELECT (title, COUNT(id), MIN(id), MAX(id)) entity = "case" and project = "CODE" GROUP BY title HAVING COUNT(id) > 1 ORDER BY count_id DESC
```

Regression scope: run fields `plan`, `milestone`, `tags`, `title` filter manual runs
(`plan = "<title>"`, `milestone = "<title>"`, `tags in ["<tag>"]`, `title ~ "<text>"`,
plus `isAutotest = false`). Plans and milestones in use:

```
SELECT (plan, milestone, COUNT(id)) entity = "run" and project = "CODE" and isAutotest = false and started >= now("-365d") GROUP BY plan, milestone
```

In an aggregate response `milestone` comes back as `milestone_title` (`null` without
one); in a row query as `milestone: {title}`. The run number comes back as `id` in a plain
row query (no SELECT), as `internal_id` with a SELECT list and no aggregate. Row
queries don't return `plan`; the filter still works. Results
also carry `milestone` and `tags`, so a milestone or tag scope can filter results
directly.

Manual runs and last activity (works when result QQL doesn't):

```
SELECT (isAutotest, COUNT(id), MAX(started)) entity = "run" and project = "CODE" and started >= now("-365d") GROUP BY isAutotest
```

A group with no rows is simply absent: with no manual runs in the window, only the
`isAutotest: "true"` row comes back; with no runs at all, `total: 0`.

The QQL run list can miss a run the REST list returns for the same window (35 vs 36
seen once, cause unknown). It does not change a recurrence shape; mention it if counts
disagree.

- At most 150 IDs per `in` list (2,000-character query limit).
- `id` comes back as a string `"CODE-101"` — strip the prefix.
- `suite` comes back as `suite_title` (a title, not an ID).
- Enums come back as numbers: automation 0 Manual, 1 To be automated, 2 Automated;
  priority 0 Not set, 1 High, 2 Medium, 3 Low; severity 0 Not set, 1 Blocker,
  2 Critical, 3 Major, 4 Normal, 5 Minor, 6 Trivial; layer 0 Not set, 1 E2E, 2 API, 3 Unit;
  run `status` 0 In Progress, 1 Passed, 2 Aborted, 3 Failed.
- A workspace can add its own priority, severity and result-status options (seen:
  severity 7 "New-2", 8 "custom"). For labels beyond the built-ins read
  `GET /v1/system_field` and map by option `id`.

## Field semantics that are easy to get wrong

- **`result.isManual` in QQL is the case's automation status**, not a per-result
  flag. It returns `"false"` for automation 0, `"true"` for 1, `2` for 2. A reporter
  result on a Manual case is still `isManual = "Manual"`. Only REST `is_api_result`
  tells an API result (reporter, MCP, script) from one marked in the UI.
- **Do not use `isManual` / `isToBeAutomated` on `case` in QQL** to mean "manual" —
  both alias "To be automated". Filter `automation in [0, 1]` (or the labels).
- **`retest` is a status reset, not an execution.** Measured: 86 of 86 retest results
  had 0 ms; 64 of them were bulk-set within one minute. A retest is usually followed
  within seconds by a 1–3 s re-mark of the same case in the same run — also not an
  execution.
- **Parameterised cases write one result per parameter row** in the same run, and the
  result carries **no row identifier**. Several results for one case in one run with no
  retest between them are rows, not duplicates.
- **Bulk submission copies one duration.** Parameter rows submitted together carry the
  same value (six rows × 1,159,833 ms) or all 0 ms; bulk-set results across cases share
  one value and one second of `end_time`.
- **Recorded manual time is weak.** Measured on a live manual project: median 12 s per
  case (the UI timer, not the work), failed/invalid times all whole seconds, outliers of
  6.7 h, 19.6 h and 44.2 h from timers left running. Treat it as a hint, not a measure.

## Limits

| Limit | Value |
|---|---|
| QQL plan | Business or Enterprise |
| QQL page | 100 rows; 10,000 matchable rows |
| QQL query length | 2,000 characters |
| Rate | 1,000 requests per minute per token |
| REST page | 100; offset up to ~100,000 |
