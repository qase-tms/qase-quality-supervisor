---
name: release-readiness
description: >-
  Produce a go / no-go release-readiness assessment for a Qase milestone, plan,
  or release: execution progress, pass rate, open blocking defects, coverage of
  release scope, and flaky-test risk — with a clear recommendation. Use when the
  user asks "are we ready to ship," release readiness, go/no-go, release sign-off,
  quality gate, or milestone status. Part of the Quality Supervisor plugin;
  powered by the Qase MCP server.
---

# Quality Supervisor — Release-Readiness Assessment

Answer one question with evidence: **can we ship?** Roll up execution progress,
pass rate, blocking defects, scope coverage, and flakiness risk for a milestone
or release into a single go / no-go with the reasons behind it.

## When to use
- "Are we ready to release <milestone>?" / "Give me a go/no-go for v2.3."
- "Release readiness for the current sprint/milestone."
- "What's blocking the release?" / "Quality gate status."

## Prerequisites
- Qase MCP server connected and authenticated.
- A **project code** and the **release scope**: a milestone, a test plan, or a
  set of runs. If not given, ask which milestone/plan defines the release.

## Tools this skill uses
- `qase_project_context` — project, milestones, environments, custom fields. Call first.
- `qql_search` — runs, results, defects scoped to the milestone/plan.
- `qase_get` — run detail (status counts), milestone, plan detail (`fields`).
- `qql_help` — confirm QQL fields if a query errors.
- `qase_regression_run` — spin up any missing scope run before sign-off.
- `qase_api` — escape hatch for run statistics / milestone rollups
  (`GET /v1/run/{code}/{id}`, `GET /v1/milestone/...`) if QQL is terse.

## Readiness dimensions (the quality gate)
Assess these five, each with a status (Pass / At risk / Fail):
1. **Execution progress** — % of in-scope cases actually run (untested = risk).
2. **Pass rate** — passed ÷ executed; weight by priority/severity.
3. **Blocking defects** — open defects of high/critical severity in scope.
4. **Scope coverage** — every release requirement/feature has run cases
   (invoke the `coverage-gap-analysis` skill for depth).
5. **Stability risk** — flaky tests among the in-scope suite that could mask
   real failures (invoke the `flakiness-stability` skill).

## Workflow

### 1. Seed context and pin the scope
Call `qase_project_context`. Resolve the release to a concrete milestone/plan.
List the in-scope runs:
```
entity = "run" and project = "DEMO" and milestone = <milestoneId>
```
(or by plan). Read each with `qase_get` / `qase_api` for status counts.

### 2. Execution progress
Compute in-scope cases vs. executed. Untested in-scope cases are the first
readiness risk. Flag suites/areas with 0 execution.
```
entity = "result" and project = "DEMO" and run in (<runIds>)
```

### 3. Pass rate (risk-weighted)
From results, compute passed / failed / blocked / skipped and pass rate. Then
weight: a failing critical case matters far more than a failing trivial one.
```
entity = "result" and project = "DEMO" and run in (<runIds>) and status = "failed"
```

### 4. Blocking defects
Find open, severe defects tied to the release:
```
entity = "defect" and project = "DEMO" and status = "open" and severity in ("major","critical","blocker")
```
Any open blocker/critical in scope ⇒ default **no-go** unless explicitly waived.

### 5. Scope coverage
Confirm each release requirement/feature has cases that ran. If gaps exist,
summarize and (optionally) invoke `coverage-gap-analysis`. Untested critical
scope is a no-go signal.

### 6. Stability risk
Check whether in-scope failures are flaky vs. real (invoke `flakiness-stability`
if needed). Flaky reds inflate failure counts; confirmed real reds block.

### 7. Decide and report
Combine the five dimensions into a recommendation:
- **GO** — high execution, high risk-weighted pass rate, no open blockers, scope
  covered, stability understood.
- **GO WITH RISKS** — minor gaps; list them and the mitigations/owners.
- **NO-GO** — open blocker/critical defect, untested critical scope, or pass
  rate below the agreed bar.
State the bar you used (make thresholds explicit; ask the user if they have a
policy). Recommend concrete unblockers.

## Output format
```
## Release Readiness — <PROJECT> / <milestone or plan> (<date>)
RECOMMENDATION: <GO | GO WITH RISKS | NO-GO>

### Quality gate
| Dimension            | Status     | Detail |
|----------------------|-----------|--------|
| Execution progress   | <P/AR/F>  | <X% of N cases executed> |
| Pass rate (weighted) | <P/AR/F>  | <X% ; crit fails: n> |
| Blocking defects     | <P/AR/F>  | <n open blocker/critical: DEF-...> |
| Scope coverage       | <P/AR/F>  | <untested scope items: ...> |
| Stability risk       | <P/AR/F>  | <flaky in-scope: n> |

### Blockers (must clear before GO)
1. <DEF-.. / untested area> — <owner/next step>

### Risks accepted (if GO WITH RISKS)
- <item> — <mitigation>

### Evidence (QQL used)
- <queries>
```

## Guardrails
- Read-only assessment; only create a run (`qase_regression_run`) or record
  results after the user approves.
- Never call `*_delete` tools here.
- Make thresholds explicit and ask for the team's gate policy rather than
  inventing one silently.
- A single open blocker/critical defect in scope defaults to NO-GO — say so
  plainly; leave waivers to the human.
- Separate flaky reds from real reds before concluding.
