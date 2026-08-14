---
description: Run a full Quality Supervisor sweep on a Qase project and produce a consolidated quality report.
argument-hint: <project-code> [milestone|plan|run]
---

Run a consolidated Quality Supervisor report for the Qase project given in
`$ARGUMENTS` (first token = project code; optional second token = the milestone,
plan, or run that scopes assessing-release-readiness).

Steps:

1. Call `qase_project_context` for the project code. If none was provided, ask
   for it before continuing. Note whether it reports any collection as
   truncated — it caps at 100 each — and treat those lists as samples.

2. Run these analyses in order, each using its Quality Supervisor skill:

   a. **finding-coverage-gaps** — top risk-ranked gaps, against the case total as
      the denominator.
   b. **analyzing-test-flakiness** — flake rate and least-stable cases. Confirm the
      time window holds results before reporting; an empty window is not a clean
      bill of health. Report genuinely flaky cases separately from
      consistently-failing ones.
   c. **triaging-test-failures** — triage the most recent finished run
      (`isEnded = true`, ordered by `started` — runs have no `created` field).
      Cluster and classify; do NOT file defects unless the user asks.
   d. **assessing-release-readiness** — only if a milestone, plan, or run was supplied.
      If it wasn't, say the gate was skipped for lack of a scope rather than
      assessing the whole project.

3. This command performs **no writes** — no cases, defects, or tags. Offer the
   write follow-ups at the end for the user to approve.

4. Output one consolidated report:

```
# Quality Report — <PROJECT> (<date>)
## Headline
<one-line health verdict; the go/no-go only if a scope was given>

## Coverage gaps (top 5)
<each against its denominator>

## Flakiness
<flake rate, window used, top unstable; consistently-failing listed apart>

## Latest run triage
<run, its stats including untested, clusters and classifications>

## Release readiness
<the five-dimension gate, or "skipped — no scope supplied">

## Data confidence
<truncated collections, empty windows, unpopulated priority/severity, any
QQL-versus-REST disagreement, and anything not measurable such as
requirement coverage>

## Recommended actions (each requires your approval)
```

Show the QQL behind each section so the user can reproduce it.

Keep the sections honest about what wasn't measured. A gap that couldn't be
assessed belongs in **Data confidence**, not omitted — an incomplete report that
looks complete is worse than one that names its limits.
