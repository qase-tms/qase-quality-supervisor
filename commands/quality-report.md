---
description: Run a full Quality Supervisor sweep on a Qase project and produce a consolidated quality report.
argument-hint: <project-code> [milestone|plan|run]
---

Run a consolidated Quality Supervisor report for the Qase project given in
`$ARGUMENTS` (first token = project code; optional second token = milestone,
plan, or run to scope release-readiness).

Steps:
1. Call `qase_project_context` for the project code. If none was provided, ask
   for it before continuing.
2. Run these analyses in order, each using its Quality Supervisor skill:
   a. **coverage-gap-analysis** — top risk-ranked coverage gaps.
   b. **flakiness-stability** — project flake rate and least-stable cases.
   c. **failure-triage** — triage the most recent completed run's failures
      (cluster + classify; do NOT file defects unless the user asks).
   d. **release-readiness** — if a milestone/plan/run was supplied, produce the
      go / no-go quality gate.
3. Do not perform any writes (no case/defect creation, no tagging) in this
   command — it is a read-only report. Offer the write follow-ups at the end.
4. Output one consolidated report:

```
# Quality Report — <PROJECT> (<date>)
## Headline: <one-line health verdict + go/no-go if scoped>
## Coverage gaps (top 5)
## Flakiness (flake rate + top unstable)
## Latest run triage (clusters + classification)
## Release readiness (if scoped)
## Recommended actions (each requires your approval)
```

Always show the QQL behind each section so the user can reproduce it.
