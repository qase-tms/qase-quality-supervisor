---
name: failure-triage
description: >-
  Triage the failures in a Qase test run: cluster them by error signature,
  separate real product bugs from automation, environment, and flaky noise,
  identify the probable cause, and file defects. Use when the user asks to
  triage a run, investigate or classify failures, asks "why did these tests
  fail", or wants defects filed for a failed run. Part of the Quality
  Supervisor plugin; powered by the Qase MCP server.
---

# Quality Supervisor — Failure Triage / Root-Cause Analysis

Turn a run full of red into a short list of causes: grouped failures, a probable
cause per group, a bug-versus-noise call, and defects for the ones that are real.

**Read the plugin's `references/qql.md` before writing any query** — it sits two
levels up from this skill's directory (`../../references/qql.md`). Field names
differ per entity and a wrong name is a hard error, not an empty result.

## When to use

- "Triage run 512." / "Why are these tests failing?"
- "Which failures are real bugs and which are noise?"
- "File defects for last night's failures."

## Prerequisites

- A **project code**. A run ID if the user has one; otherwise find the latest.
- QQL access (Business/Enterprise) for the run lookup and history checks. The
  row-level work goes through the REST API and needs no QQL.

## Tools

- `qase_project_context` — project metadata. Call first.
- `qql_search` — find the run, check per-case history.
- `qase_api` — fetch the run's failing results (see step 3: QQL cannot do this).
- `qase_get` — detail on a specific case when writing up a cause.
- `qase_triage_defect` — create a defect (write step, needs approval). Read the
  warning in step 6 before using it.

## Workflow

### 1. Find the run and its real failure count — one query

```
entity = "run" and project = "CODE" and status = "failed" ORDER BY started DESC
```

Runs have **no `created` field** — `started` and `ended` are the only
timestamps, so this is how "the latest run" is expressed.

The response carries both `run_id` and a `stats` object with per-status counts.
**That `stats` block is your authoritative failure count.** Take the totals from
it and never recompute them by counting rows you fetched — rows come in pages,
`stats` does not.

If the user named a run, query it by id instead: `entity = "run" and project =
"CODE" and id = 512`.

### 2. Frame the scale before looking at details

From `stats`: total, failed, blocked, skipped, invalid, untested. State these up
front. A run with 3 failures out of 5 and one with 3 out of 4,000 are different
problems, and the ratio changes what triage is worth doing.

Note `untested` separately — those tests never ran, which is a gap, not a
failure, and it is easy to misread as green.

### 3. Fetch the failing results — via REST, not QQL

QQL **cannot scope results to a specific run.** The `result` entity has no
run-ID field; `run` matches the run *title*, and titles repeat (autotest runs
are routinely named by timestamp or branch). Filtering by title will silently
mix in other runs' results.

Use `qase_api` instead:

```
GET /v1/result/{code}?run={run_id}&status=failed&limit=100
```

Read **`filtered`** from the response for the count matching your filter —
`total` is the project-wide count and ignores the filter entirely. Cross-check
`filtered` against `stats.failed` from step 1; if they disagree, say so rather
than picking one.

If `filtered` exceeds 100, paginate with `offset` until you have them all, or
state how many you examined out of how many exist. Add `&status=blocked` as a
second pass if the run has blocked results worth triaging.

Each row gives you `case_id`, `status`, `stacktrace`, `comment`, `steps`,
`time_spent_ms`, and `hash`. The stacktrace is what makes clustering possible
and it is **only** available on these rows — it is not a queryable field, so
there is no way to group by it server-side.

Note: results carry **no environment or configuration**. If environment matters,
get it from the run (`run.environment`), which applies to the whole run.

### 4. Cluster by cause, not by symptom

Group the failures you fetched:

- **Same error signature** — normalise the stacktrace first (strip line numbers,
  paths, timestamps, IDs), then group by exception type plus the first
  meaningful frame. This is the strongest signal.
- **Same suite or feature area** — points at one broken area.
- **Same fixture, setup, or shared step** — points at test infrastructure.
- **All failures in the run** — a single infra or auth failure often explains
  every red; check this before triaging 200 items individually.

Report the cluster count next to the failure count. Collapsing 40 failures into
3 causes is the useful output; a list of 40 is not.

### 5. Classify each cluster

One label per cluster, with the evidence that supports it:

- **Product bug** — deterministic, asserts on real behaviour → defect candidate.
- **Automation issue** — selector drift, timing, bad assertion, stale test data
  → fix the test.
- **Environment/infra** — auth, network, service unavailable, whole-run failure
  → fix the environment.
- **Flaky** — the same case has passed and failed recently → hand to
  `flakiness-stability`; do **not** file a product bug.

Check history per case before calling anything flaky:

```
entity = "result" and project = "CODE" and caseId = 234 ORDER BY ended DESC
```

Note `caseId` (not `case`, which is the title) and `ended` (results have no
`created`). Mixed pass/fail history means flaky. **Failures only, never a pass,
means the opposite** — that is a real, persistent failure, so treat it as a bug
candidate rather than noise.

### 6. File defects — only after approval, and only with honest claims

**Before creating anything, search for an existing defect:**

```
entity = "defect" and project = "CODE" and status = "Open"
```

Match on title and error signature; if one already covers the cause, reference
it instead of creating a duplicate.

Then, per confirmed product-bug cluster, one defect per cause — not one per
failing test.

`qase_triage_defect` needs `title`, `actual_result`, and `severity`. The tool's
schema marks the last two optional, but the API requires all three, so a call
without them fails. Severity is one of: `blocker`, `critical`, `major`,
`normal`, `minor`, `trivial`, `undefined`.

**Two things this tool does not do, despite appearances:**

1. It does **not** link results or runs to the defect. It accepts
   `failed_result_ids` and `run_id`, discards them, and then prints
   `Linked results: N` and returns `linked_results: N`. That number is the
   length of the list you passed, not work performed. **Never repeat it to the
   user as if the linkage exists.**
2. Qase's API has no defect-side way to attach results. The `results` and `runs`
   fields on a defect are populated from the runner side, when a result is
   submitted marked as a defect — not by anything this plugin can call.

So make the defect self-sufficient: put the run ID, the affected case IDs, the
normalised error signature, and the environment into `actual_result` and
`description`. That text is the only durable connection between the defect and
the evidence, so it has to carry it.

Report the defect IDs you created and state plainly that results were not
linked automatically.

## Output format

```
## Triage — <PROJECT> run <ID> (<run title>)
Run stats: <total> tests · <failed> failed · <blocked> · <skipped> · <untested> untested
Examined: <N> failing results (of <filtered>)  |  Clusters: <K>

### Cluster 1 — <normalised error signature>
- Cases: <ids>  ·  Occurrences: <n>  ·  Environment: <run environment, if any>
- Classification: <Product bug | Automation | Environment | Flaky> (confidence: H/M/L)
- Probable cause: <one or two lines, tied to the evidence>
- Action: <file defect | fix test | fix env | route to flakiness-stability>

### Summary
- Product bugs: <n>  ·  Automation: <n>  ·  Environment: <n>  ·  Flaky: <n>
- Untested in this run: <n> — never executed, not failures

### Recommended actions (each needs your approval)
- <e.g. "File one defect for the auth-timeout cluster covering C-12, C-14, C-19">

### Evidence
<the queries and API calls used, verbatim>
```

## Guardrails

- Read and analyse first; create defects only after the user approves.
- One defect per root cause, and search for an existing open defect first.
- Never call a `*_delete` tool. (A hook blocks them anyway.)
- Don't over-claim causation — give a confidence level and cite the evidence.
- Take counts from run `stats`, not from the rows you happened to fetch; if you
  examined a subset, say so.
- Never claim results were linked to a defect — the tooling cannot do it.
- Suspected flaky goes to `flakiness-stability`, not into a product bug.
