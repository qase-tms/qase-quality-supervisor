---
name: analyzing-test-flakiness
description: >-
  Find genuinely flaky tests in a Qase project — cases that both pass and fail —
  and separate them from tests that are simply broken. Use when the user asks
  which tests are flaky, unreliable, unstable, intermittent, or non-deterministic;
  about test stability, flakiness, or the flake rate; which tests pass sometimes
  and fail other times, or fail randomly; which tests to quarantine, mute, or
  flag as flaky; or whether a specific test is flaky or a real regression.
---

# Quality Supervisor — Flakiness / Stability Analysis

Find tests that pass and fail without the code changing, quantify how unstable
they are, and recommend what to do about each one.

**Read the plugin's `references/qql.md` before writing any query** — it sits two
levels up from this skill's directory (`../../references/qql.md`). Field names
differ per entity and a wrong name is a hard error, not an empty result. The
queries below are verified; if you deviate from them, check the reference first.

## When to use

- "Which tests are flaky?" / "Show me our least stable tests."
- "What's our flake rate?" / "Which tests should we quarantine?"
- "Is case 123 flaky, or actually broken?"

## The distinction that matters

A test that fails repeatedly is not necessarily flaky. There are two very
different populations, and they need opposite responses:

| | Evidence | What it is | Response |
|---|---|---|---|
| **Flaky** | both passes **and** failures in the window | non-deterministic | quarantine / fix the test |
| **Consistently failing** | failures only, never passed | a real regression, or a permanently broken test | fix the product, or hand to `triaging-test-failures` |

Counting failures alone cannot tell these apart, and in practice most
high-failure cases are in the second group. **Never report a case as flaky
without having seen it pass in the same window.** If you only have failure
counts, you have candidates, not findings.

## Prerequisites

- A **project code**. If the user didn't give one, ask — never guess.
- QQL access (Business/Enterprise). If `qql_search` returns a permission error,
  say so and stop; there is no fallback path for this analysis.

## Tools

- `qase_project_context` — project metadata. Call first.
- `qql_search` — every step below. Use aggregation, not row fetching.
- `qase_get` — detail on a specific case once you have IDs worth explaining.
- `qase_case_upsert` — set `is_flaky: true` on confirmed flakes (write step,
  needs approval).
- `qase_api` — for anything QQL can't reach (see Limits below).

## Workflow

### 1. Seed context and settle the window

Call `qase_project_context` for the project.

Default window: last 30 days. Before analysing, confirm the window actually
contains data:

```
SELECT (status, COUNT(*)) entity = "result" and project = "CODE" and ended >= now("-30d") GROUP BY status
```

If this returns no groups, the window is empty — **do not report "no flaky
tests"**. Widen it (`-3m`, then `-12m`), and state in the report which window
you ended up using and why. A project whose CI stopped a month ago has plenty
of flakiness history; it is just older than your default.

This query also gives you the project's overall status distribution, which is
the denominator for the flake rate later. Map the integer status codes back to
labels using `references/qql.md`.

### 2. Find candidates — cases that failed more than once

```
SELECT (caseId, COUNT(*)) entity = "result" and project = "CODE" and status = "failed" and ended >= now("-30d") GROUP BY caseId HAVING COUNT(*) >= 2
```

One failure is noise; two or more is worth examining. This is one call instead
of paging through every result row, and `caseId` is a stable key — group by
`caseId`, not `case`, because `case` is the title and titles are neither unique
nor stable.

Note the `total`: it is the number of candidate cases. If it exceeds the rows
you received, paginate with `offset` until you have them all.

### 3. Get the pass/fail split for those candidates

Batch the candidate IDs — at most **150 per query**, to stay inside the
2,000-character query limit with room to spare:

```
SELECT (caseId, status, COUNT(*)) entity = "result" and project = "CODE" and caseId in (101, 102, …) and ended >= now("-30d") GROUP BY caseId, status
```

Repeat for every batch until all candidates are covered. Then classify each:

- passes **and** failures → **flaky**
- failures only → **consistently failing**; exclude from the flaky list and
  report separately, recommending `triaging-test-failures` rather than quarantine
- also note blocked/skipped/invalid counts: a case that is mostly skipped isn't
  stable evidence of anything, so say so instead of ranking it

### 4. Quantify

For each flaky case compute, over the window:

- **runs** = total results
- **fail rate** = failures ÷ (passes + failures)
- **project flake rate** = flaky cases ÷ cases that ran at least once

Rank by **fail rate × runs**: a test that runs every hour and fails a third of
the time costs far more than one that runs twice a month.

State plainly what this measurement is and is not. It shows that a case both
passed and failed in the window — coexistence, not alternation. QQL aggregation
cannot see the *order* of results, so **do not report a "transition count" or
claim to have detected a pass→fail→pass pattern.** You did not measure that.

Optional secondary signal, useful for timing-related flakiness:

```
SELECT (caseId, AVG(timeSpent), MIN(timeSpent), MAX(timeSpent), COUNT(*)) entity = "result" and project = "CODE" and caseId in (…) and ended >= now("-30d") GROUP BY caseId
```

A case whose duration swings by orders of magnitude is likely waiting on
something non-deterministic. Note it as a hypothesis, not a diagnosis.

### 5. Cross-check Qase's own flag

```
entity = "case" and project = "CODE" and isFlaky = true
```

Use this to reconcile, **not** as a shortcut — the flag is only as good as
whoever last set it, and a project can have many real flakes with the flag
unset. Two useful comparisons:

- flagged but stable in your window → propose clearing the flag
- flaky in your window but unflagged → propose setting it (step 7)

Report the disagreement; it tells the team how much to trust the flag.

### 6. Report

```
## Flakiness & Stability — <PROJECT>
Window: <the window you used, and why if it isn't the default 30d>
Sample: <N> results across <M> cases that ran  |  candidates examined: <C>

### Confirmed flaky (ranked by fail rate × runs)
| Case | ID | Runs | Passed | Failed | Fail rate | Recommend |
|------|----|------|--------|--------|-----------|-----------|
| ... | 123 | 40 | 28 | 12 | 30% | quarantine + fix waits |

### Not flaky — consistently failing (<N>)
These never passed in the window. They are regressions or permanently broken
tests, not flakiness: <case IDs>. → run `triaging-test-failures` on these.

### Qase isFlaky flag
Flagged: <n> · agreeing with this analysis: <n> · flagged but stable: <n> ·
flaky but unflagged: <n>

### Project flake rate
<X>% of cases that ran in the window were flaky.

### Recommended actions (each needs your approval)
- Set is_flaky on: <cases>
- Investigate as regressions: <cases>

### Evidence
<the QQL queries used, verbatim>
```

Always report the window and the sample size. If anything was truncated — a
`total` larger than what you fetched, candidates you didn't get to — say which
and how many. A number presented without its denominator will be read as
project-wide truth.

### 7. Write back (only after explicit approval)

`qase_case_upsert` with `is_flaky: true` marks a case flaky in Qase natively.
Prefer this over adding a tag: it feeds Qase's own reporting and makes the
`isFlaky` query useful for everyone afterwards.

Show the list and get a yes first. Report the case IDs you changed.

## Limits — be honest about these

- **No environment data on results.** The `result` entity has no `environment`
  field, so "flaky only on staging" cannot be answered from result rows. If the
  user asks, go through `run.environment` to find that environment's runs and
  analyse those, or say the breakdown isn't available. Don't guess.
- **You cannot execute tests.** `qase_regression_run` creates a run from case
  IDs; it does not run anything. Re-running N times to confirm flakiness is a
  CI or Playwright MCP job. You may create the run and hand it off — but never
  imply you confirmed flakiness by executing it.
- **Muting is not exposed.** QQL can read `isMuted`, but `qase_case_upsert`
  cannot set it. True quarantine needs `qase_api`, or the user does it in the
  UI. Recommend quarantine, and be clear about which of the two you mean.
- **Aggregation sees counts, not sequence.** See step 4.

## Guardrails

- Analysis is read-only. Writes only after the user approves.
- Never call a `*_delete` tool. (A hook blocks them anyway.)
- Never label a case flaky without an observed pass in the window.
- Distinguish flaky from a genuine regression before recommending quarantine —
  quarantining a real bug hides it.
- State the window and the flake-rate definition in every report.
- An empty result set is not evidence of stability; check the window has data.
