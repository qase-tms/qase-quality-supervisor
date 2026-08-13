---
name: release-readiness
description: >-
  Produce an evidence-backed go / no-go assessment for a Qase release scope — a
  milestone, a test plan, or a set of runs — covering execution progress, pass
  rate, blocking defects, untested scope, and flaky-test risk. Use when the user
  asks "are we ready to ship", release readiness, go/no-go, release sign-off,
  quality gate, or milestone status. Part of the Quality Supervisor plugin;
  powered by the Qase MCP server.
---

# Quality Supervisor — Release-Readiness Assessment

Answer one question with evidence: **can we ship?**

**Read the plugin's `references/qql.md` before writing any query** — it sits two
levels up from this skill's directory (`../../references/qql.md`). Field names
differ per entity and a wrong name is a hard error, not an empty result.

## When to use

- "Are we ready to release <milestone>?" / "Give me a go/no-go for 2.3."
- "What's blocking the release?" / "Quality gate status."

## The failure mode this skill exists to avoid

A release gate built on failure counts says GO when it should say "I don't know".
Three ways that happens, all confirmed against real projects:

- **Nothing ran.** A run with 72 tests and 72 untested has zero failures. Zero
  failures reads as green; it means the testing hasn't happened.
- **Defects aren't tracked in Qase.** A project with no defects at all yields no
  blocking defects. That is not a clean bill of health, it is a blind spot.
- **The scope resolved to nothing.** An empty query result and a passing scope
  look identical if you only count failures.

So: **before assessing, establish that you are looking at something.** If scope,
execution, or defect data is absent, the answer is "insufficient evidence", not
GO.

## Prerequisites

- A **project code** and a **release scope**. If the user hasn't named one, ask
  which milestone, plan, or runs define the release — do not default to the whole
  project.
- QQL access (Business/Enterprise), plus `qase_api` for cross-checks.

## Tools

- `qase_project_context` — project, milestones, environments. Call first.
- `qql_search` — scope resolution, defects, flaky cases.
- `qase_api` — run listings and stats, and the REST cross-check in step 6.
- Delegate depth: `coverage-gap-analysis` for untested scope,
  `flakiness-stability` for stability risk.

## Workflow

### 1. Resolve the scope — by title, never by ID

`milestone` and `plan` match **titles**, not IDs. `milestone = 1` fails with
`invalid value: 1`, and `run in (1, 2)` fails the same way.

```
entity = "run" and project = "CODE" and milestone = "Release 2.3"
entity = "run" and project = "CODE" and plan = "Regression suite"
entity = "run" and project = "CODE" and id = 512
```

Get the titles from `qase_project_context`. If the milestone yields no runs, say
so and stop for instructions — an empty scope cannot be assessed.

**Do not scope results by milestone.** `result.milestone` is inherited from the
*case*, not from the run, so on a project where runs carry the milestone but
cases don't, `entity = "result" and milestone = "…"` returns nothing while the
runs plainly have results. Go through the runs.

### 2. Execution progress — from run stats, and mind `untested`

Each run entity carries a `stats` object: `total`, `untested`, `passed`,
`failed`, `blocked`, `skipped`, `retest`, `in_progress`, `invalid`. Sum it across
the scope's runs. This is exact and costs nothing beyond the queries you already
ran.

- **executed** = `total − untested`
- **execution progress** = executed ÷ total

`untested` is the number that decides most real go/no-go calls, and it is the one
a failure-count approach never sees. Report it before anything else. Anything
materially short of full execution is **At risk** at best, regardless of how
clean the executed part looks.

### 3. Pass rate — state the denominator

**pass rate = passed ÷ executed**, not ÷ total. Dividing by total conflates "not
run" with "failed"; dividing by executed and hiding the untested count flatters
the release. Report both numbers together.

For the failure breakdown in one call:

```
SELECT (status, COUNT(*)) entity = "result" and project = "CODE" and run = "<run title>" GROUP BY status
```

Aggregated responses return status as an integer: 1 = Passed, 2 = Failed,
3 = Blocked, 4 = Retest, 5 = Skipped, 8 = Invalid.

Weight by priority or severity **only after checking they're populated** — see
`coverage-gap-analysis` step 5. If most cases are "Not set", say the project has
no usable risk metadata instead of ranking on a handful of tagged cases.

### 4. Blocking defects — and whether defects exist at all

Two queries, in this order. The first is the one that prevents a false GO:

```
entity = "defect" and project = "CODE"
entity = "defect" and project = "CODE" and status = "Open" and severity in ("blocker","critical")
```

- first query returns **0** → the project does not track defects in Qase. Report
  this dimension as **Unknown**, never as Pass, and say the team's blockers live
  somewhere this assessment cannot see.
- first > 0, second = 0 → genuinely no blocking defects. That is a Pass.

Defect status values are `Open`, `In progress`, `Resolved`, `Invalid`. Severity
integers in aggregates: 0 = Not set, 1 = Blocker, 2 = Critical, 3 = Major,
4 = Normal, 5 = Minor, 6 = Trivial. Note that severity is frequently left unset —
a "Not set" defect may well be a blocker nobody triaged, so count it separately
rather than assuming it's minor.

Scope defects to the release with `and milestone = "Release 2.3"` when defects
carry milestones; if they don't, assess project-wide and say that's what you did.

### 5. Untested scope and stability risk

- **Untested scope**: the `untested` count from step 2 is the direct answer. For
  which areas are uncovered, invoke `coverage-gap-analysis`.
- **Stability risk**: flaky tests inside the scope inflate or mask failures.

```
entity = "case" and project = "CODE" and isFlaky = true
```

For a real assessment rather than the flag's word, invoke
`flakiness-stability` — the flag is often stale or unset. Flaky reds must be
separated from real reds before you conclude anything about the pass rate.

### 6. Cross-check the numbers before deciding

QQL and the REST API do not always agree — they are different views of the data,
and the gap can be large. Observed on real projects: a run that QQL returns as
live (and not deleted) which REST reports as "Run not found"; run and defect
totals differing by a factor of two or three between the two.

For a go/no-go, verify the decisive numbers a second way:

```
GET /v1/run/{code}?limit=100          → runs and their stats
GET /v1/result/{code}?run={id}&status=failed   → read `filtered`, not `total`
```

If the two sources disagree, **report the disagreement as part of the finding**
and lower your confidence. Do not average them or pick the friendlier one. A
release decision resting on a number the product's own UI won't reproduce is
worse than no decision.

### 7. Decide, and be explicit about the bar

Ask the user for the team's gate policy. If they don't have one, state the bar
you applied rather than presenting it as objective.

- **GO** — scope fully executed, pass rate above the bar, no open
  blocker/critical, untested scope empty, stability understood.
- **GO WITH RISKS** — minor gaps, each listed with its mitigation and owner.
- **NO-GO** — an open blocker or critical, untested critical scope, or pass rate
  below the bar.
- **INSUFFICIENT EVIDENCE** — scope resolved empty, execution materially
  incomplete, or defect tracking unused. This is a real verdict; use it instead
  of guessing. It is not the same as NO-GO, and the difference tells the team
  what to go do.

A single open blocker or critical in scope defaults to NO-GO. Say so plainly and
leave any waiver to the human.

## Output format

```
## Release Readiness — <PROJECT> / <scope: milestone|plan|runs>
RECOMMENDATION: <GO | GO WITH RISKS | NO-GO | INSUFFICIENT EVIDENCE>
Bar applied: <the thresholds used, and whose policy they are>

### Quality gate
| Dimension | Status | Detail |
|---|---|---|
| Execution progress | P/AR/F | <executed>/<total> (<x>%) · untested: <n> |
| Pass rate | P/AR/F | <passed>/<executed> (<x>%) · failed: <n> |
| Blocking defects | P/AR/F/Unknown | <n> open blocker+critical <or "project tracks no defects"> |
| Untested scope | P/AR/F | <n> tests never executed in scope |
| Stability risk | P/AR/F | <n> flaky in scope <or "not assessed"> |

### Blockers (must clear before GO)
1. <item> — <owner / next step>

### Risks accepted (if GO WITH RISKS)
- <item> — <mitigation>

### Data confidence
<any QQL/REST disagreement, empty scopes, or unpopulated metadata that limits
this assessment>

### Evidence
<the queries and API calls used, verbatim>
```

## Guardrails

- Read-only. Creating a run (`qase_regression_run`) or recording results needs
  explicit approval.
- Never call a `*_delete` tool. (A hook blocks them anyway.)
- Make the bar explicit; ask for the team's policy rather than inventing one.
- Never report a dimension as Pass because its data is absent — absent data is
  Unknown.
- Always show `untested` next to the pass rate.
- Separate flaky reds from real reds before concluding.
- Scope by title, not ID, and confirm the scope is non-empty before assessing.
- Surface QQL/REST disagreement instead of resolving it silently.
