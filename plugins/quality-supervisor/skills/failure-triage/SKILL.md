---
name: failure-triage
description: >-
  Triage failing tests in a Qase run: cluster failures, classify each as
  product bug vs. automation/environment issue, find the likely root cause,
  and create + link defects. Use when the user asks to triage a run, "why did
  these tests fail," investigate failures, classify failures, or file bugs for
  a failed run. Part of the Quality Supervisor plugin; powered by the Qase MCP
  server.
---

# Quality Supervisor — Failure Triage / Root-Cause Analysis

Turn a pile of red results into an actionable triage: grouped failures, a
probable cause for each cluster, a product-bug-vs-noise call, and defects
created and linked back to the failing results.

## When to use
- "Triage run 42 in project ABC." / "Why are these tests failing?"
- "Which failures are real bugs vs. flaky/env issues?"
- "File defects for the failures in the last run and link them."

## Prerequisites
- Qase MCP server connected and authenticated.
- A **project code** and ideally a **run ID**. If no run given, find the latest.

## Tools this skill uses
- `qase_project_context` — project metadata (defect fields, users, envs). Call first.
- `qql_search` — find failing results and prior history of the same cases.
- `qase_get` — pull full detail on a run, result, or case (with `fields`).
- `qase_triage_defect` — **primary write tool**: create a defect from a test
  failure and link it to the failing result(s) in one call.
- `qase_defect_upsert` — create/update a defect directly, or set
  `status:"resolved"`; check for an existing matching defect before creating.
- `qql_help` — verify QQL fields if a query is rejected.
- `qase_discover_tools` — activate extra tools if needed.
- `qase_api` — escape hatch (`/v1/...`) for run stats or result details a tool
  doesn't surface.

## Workflow

### 1. Seed context and find the run
Call `qase_project_context`. Identify the target run:
```
entity = "run" and project = "DEMO" order by created desc
```
Read run detail with `qase_get` (type `run`, code + id) to get status counts.

### 2. Pull the failures
Get failing results for the run:
```
entity = "result" and project = "DEMO" and run = <runId> and status in ("failed","blocked")
```
For each result capture: case_id, status, error/stacktrace message, duration,
environment, and configuration. Use `qase_get` on a result or `qase_api`
(`GET /v1/result/...`) for the full error payload if QQL is terse.

### 3. Cluster failures
Group by shared signal so you triage causes, not symptoms:
- Same error message / stacktrace signature.
- Same suite or feature area.
- Same environment/configuration (points to env, not product).
- Same setup/teardown or shared step (points to fixture, not feature).
A single infra failure often explains many reds — collapse them.

### 4. Classify each cluster
Assign one label with a one-line justification:
- **Product bug** — deterministic, assertion on real behavior, aligns with a
  recent change. → defect candidate.
- **Automation issue** — selector/locator drift, timing, bad assertion, test
  data. → fix the test.
- **Environment/infra** — network, auth, service down, only one env affected. → env fix.
- **Flaky** — same case has mixed pass/fail history (hand off to the
  `flakiness-stability` skill rather than filing a bug).
Check history to inform the call:
```
entity = "result" and project = "DEMO" and case = <caseId> order by created desc
```

### 5. Find probable root cause
For each product-bug cluster, state the most likely cause from the evidence:
the failing assertion, the expected/actual diff, the first failing step,
correlation with an environment or a recent milestone/requirement change.
Be explicit about confidence and what would confirm it.

### 6. Create and link defects (only on confirmation)
For confirmed product-bug clusters:
1. **Search first** to avoid duplicates:
   ```
   entity = "defect" and project = "DEMO" and status = "open"
   ```
   Match on title/error signature; if found, link to it instead of creating.
2. Create + link in one step with `qase_triage_defect` — pass defect fields and
   the failing result(s)/case(s) to link. One defect per distinct root cause,
   not one per red test.
3. Write a crisp defect: title = the symptom, body = affected cases, error
   signature, environment, steps to reproduce, suspected cause.
4. Report every defect created with its ID and the results linked.
Do not file defects for automation/env/flaky clusters — route those instead.

## Output format
```
## Triage Report — <PROJECT> run <ID> (<date>)
Failures: <N> across <M> cases  |  Clusters: <K>

### Cluster 1 — <short signature>
- Cases: <ids>  | Env: <env>  | Occurrences: <n>
- Classification: <Product bug | Automation | Environment | Flaky> (confidence: H/M/L)
- Probable root cause: <one/two lines>
- Action: <defect DEF-12 created & linked | fix test | route to flakiness skill>

### Cluster 2 — ...

### Summary
- Product bugs filed: N (DEF-...)
- Automation issues: N
- Environment issues: N
- Flaky (routed): N
```

## Guardrails
- Read and analyze first; only write defects after the user confirms.
- One defect per root cause; always search for an existing open defect first.
- Never call `*_delete` tools here.
- Don't over-claim causation — label confidence and cite the evidence.
- Suspected flaky? Hand to `flakiness-stability`; don't file a product bug.
