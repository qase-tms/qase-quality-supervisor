---
name: flakiness-stability
description: >-
  Detect and quantify flaky and unstable tests in a Qase project by analyzing
  result history, then recommend actions (quarantine, re-run to confirm, fix).
  Use when the user asks about flaky tests, test stability, intermittent
  failures, "which tests are unreliable," flake rate, or wants to quarantine or
  confirm flakiness. Part of the Quality Supervisor plugin; powered by the Qase
  MCP server.
---

# Quality Supervisor — Flakiness / Stability Analysis

Find tests that pass and fail without code changing, quantify how unstable they
are, and recommend what to do — confirm via re-run, quarantine, or fix. Flaky
tests erode trust in the suite; this skill separates real signal from noise.

## When to use
- "Which tests are flaky?" / "Show me our least stable tests."
- "What's our flake rate this month?"
- "Confirm whether case 123 is flaky." / "Quarantine the flaky tests."

## Prerequisites
- Qase MCP server connected and authenticated.
- A **project code**. A time window helps (default to last 30 days).

## Tools this skill uses
- `qase_project_context` — project metadata + custom fields. Call first.
- `qql_search` — history of results per case; Qase's `isFlaky` signal if present.
- `qase_get` — detail on a case or result.
- `qql_help` — confirm field names (e.g. `isFlaky`, `automation`, `status`).
- `qase_regression_run` — **confirm flakiness by re-running** suspect cases
  (set up a run from case IDs / suite / plan in one call).
- `qase_result_record` — record results of confirmation re-runs if executed
  outside CI; or `qase_ci_report` for a full CI-style run+results+complete.
- `qase_case_upsert` — tag/quarantine a case (label or custom field) on approval.
- `qase_api` — escape hatch for result-history endpoints if QQL is insufficient.

## What "flaky" means here
A test is flaky when it produces **different results (pass/fail) for the same
code and environment** over time. Quantify with a **flake rate** = transitions
between pass and fail ÷ total runs, over the window. High transition count with
no correlated code/env change ⇒ flaky, not a genuine regression.

## Workflow

### 1. Seed context
Call `qase_project_context`. Note whether the workspace tracks an `isFlaky`
attribute and any relevant custom fields.

### 2. Get the candidate set (fast path)
If Qase already flags flakiness, start there:
```
entity = "case" and project = "DEMO" and isFlaky = true
```
(If the field name errors, call `qql_help` topic `syntax`/`entities` to confirm.)

### 3. Build history-based evidence (robust path)
Pull recent results and compute stability per case:
```
entity = "result" and project = "DEMO" and time_created >= now("-30d") order by created desc
```
For each case_id, order results by time and count pass↔fail transitions.
Compute per case:
- runs in window, pass count, fail count
- transition count and flake rate
- environments/configs involved (flaky in only one env ⇒ likely env, not test)
Rank by flake rate × execution frequency (a flaky test that runs often hurts most).

### 4. Confirm suspected flakes (optional, on request)
To move from "suspected" to "confirmed," re-run the candidates several times
with no code change:
1. `qase_regression_run` — create a run from the suspect case IDs.
2. Execute (in CI, or record outcomes via `qase_result_record` /
   `qase_ci_report`) N times.
3. Mixed results across identical runs = confirmed flaky.

### 5. Recommend actions
For each unstable case, recommend one:
- **Quarantine** — move out of the gating suite / tag so it doesn't block
  releases, while keeping it visible. Apply via `qase_case_upsert` (label or
  custom field) after user approval.
- **Fix** — point at the likely cause (timing/waits, order dependence, shared
  state, network, non-deterministic data).
- **Confirm** — if evidence is thin, propose a re-run batch (step 4).
- **Retire** — if a case is chronically flaky and low value.

### 6. Report
Give a ranked table plus a project-level flake rate and trend.

## Output format
```
## Flakiness & Stability Report — <PROJECT> (window: last 30d)
Project flake rate: <X%>  |  Unstable cases: <N> of <total run>

### Least stable (ranked)
| Case | Runs | Pass | Fail | Transitions | Flake rate | Envs | Recommend |
|------|------|------|------|-------------|-----------|------|-----------|
| C-123 Login retry | 40 | 31 | 9 | 12 | 30% | staging | Quarantine + fix waits |
| ...  |

### Notes
- Env-specific instability: <cases only flaky on X>
- Confirmed via re-run: <cases>  |  Suspected only: <cases>

### Recommended actions
- Quarantine: <cases> (say the word to tag them)
- Fix: <cases> — <cause>
- Re-run to confirm: <cases>
```

## Guardrails
- Analysis is read-only; quarantining/tagging via `qase_case_upsert` and any
  re-run recording happen only after the user approves.
- Distinguish **flaky** (non-deterministic) from a **genuine regression**
  (consistent fail after a change) — don't quarantine a real bug.
- Never call `*_delete` tools here.
- State the window and the flake-rate definition in every report.
- If `isFlaky` isn't available, fall back to history-based computation.
