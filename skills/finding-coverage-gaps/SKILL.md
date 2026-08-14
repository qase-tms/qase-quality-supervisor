---
name: finding-coverage-gaps
description: >-
  Find where a Qase project's test coverage is thin. Use when the user asks about
  test coverage or coverage gaps; what isn't tested, untested areas, or what is
  missing tests; which cases are still manual, not automated, or yet to be
  automated; which cases have never been run or executed; which suites are empty,
  thin, or hold no cases; how much of the project is automated; which cases are
  stale or outdated; or wants test cases drafted to close a gap.
---

# Quality Supervisor — Coverage / Gap Analysis

Find where a project's coverage is thin, rank the gaps by what they actually
risk, and — on request — draft the missing cases.

**Read the plugin's `references/qql.md` before writing any query** — it sits two
levels up from this skill's directory (`../../references/qql.md`). Field names
differ per entity and a wrong name is a hard error, not an empty result.

## When to use

- "Where are our coverage gaps?" / "What isn't tested in project ABC?"
- "Which cases aren't automated?" / "Which suites are empty?"
- "What's never been run?" / "Generate the missing cases for <feature>."

## What "coverage" can and cannot mean here

Decide which question you are answering and say so — these are different gaps
with different fixes:

| Lens | Question | Available? |
|---|---|---|
| **Execution** | which cases have never run? | yes |
| **Automation** | which cases are still manual? | yes |
| **Structure** | which suites are empty or unfiled? | yes |
| **Freshness** | which cases are stale? | yes |
| **Requirements** | which requirements have no tests? | **partly — see below** |

**Requirements are readable; their coverage is not.** You can query them —

```
SELECT (status, COUNT(*)) entity = "requirement" and project = "CODE" GROUP BY status
entity = "requirement" and project = "CODE" and status = "Implemented"
```

— and the response carries `id`, `title`, `description`, `status`, `type`, and
`parent_id`, so requirement hierarchy (epic → user story → feature) is available
too.

What is **not** available is the link between a requirement and its test cases.
No field on either entity exposes it, in either direction; nothing is filterable
on it; `qase_get` doesn't support requirements; and there is no requirements
endpoint in the REST API. So "which requirements have no tests" cannot be
answered, only "which requirements exist, and in what state".

If the user asks for requirement coverage, say that directly. A useful honest
substitute — clearly labelled as a proxy, not coverage — is to list requirements
marked `Implemented` and let the team judge whether tests exist for them.
Never present it as measured coverage.

Note when reporting: QQL **filters** on labels (`type = "User story"`, which is
case-sensitive here) while the **response** returns slugs (`user-story`). Map
them rather than quoting raw slugs at the user.

## Prerequisites

- A **project code**. If the user didn't give one, ask — never guess.
- QQL access (Business/Enterprise) for everything except the suite listing.

## Tools

- `qase_project_context` — project metadata. Call first.
- `qql_search` — all the counting below. Use aggregation, not row fetching.
- `qase_api` — the suite listing (`GET /v1/suite/{code}`), which is the only way
  to see empty suites.
- `qase_case_upsert` — create one case; `qase_case_bulk_create` for many in one
  call. Both are core tools (write steps).
- `qase_suite_upsert` — **discoverable, not core**: activate it first with
  `qase_discover_tools` or the call will fail with "unknown tool".

## Workflow

### 1. Establish the denominator

```
entity = "case" and project = "CODE"
```

Take `total`. Every gap below is a fraction of this, and a gap count without it
is meaningless — "40 cases aren't automated" reads very differently against 50
cases than against 18,000.

Call `qase_project_context` too, for the suite tree and milestones. If it reports
a truncated collection, respect that: it caps at 100 per collection, so on a
large project treat its suite list as a sample, not the tree.

### 2. Execution coverage — what has never run

Two aggregate queries, no enumeration:

```
entity = "case" and project = "CODE"
SELECT (COUNT(id)) entity = "result" and project = "CODE" GROUP BY caseId
```

The second query's `total` is the number of **distinct cases that have at least
one result**. Subtract it from the case total and you have the never-executed
count — one number, two calls, no matter how large the project.

Two caveats to state rather than hide:

- results survive their cases, so a deleted case can still contribute a group.
  That inflates the executed count and makes the gap a **lower bound**.
- this counts "ever executed". For "executed recently", add
  `and ended >= now("-90d")` to the second query and label it accordingly — a
  case last run two years ago is a different kind of gap.

To **name** the never-executed cases rather than count them, scope down first —
one suite (`suiteTree = "…"`), one milestone, or one priority — and compare the
case list against that scope's executed IDs. Enumerating them project-wide means
paging both lists in full; don't attempt it on a large project, and say why.

### 3. Automation coverage

```
SELECT (automation, COUNT(*)) entity = "case" and project = "CODE" GROUP BY automation
```

One query, whole distribution. Aggregated responses return the enum as an
integer: 0 = Manual, 1 = To be automated, 2 = Automated.

`To be automated` is the interesting bucket — someone already decided those
should be automated and it hasn't happened. Report it separately from `Manual`
rather than lumping both into "not automated".

### 4. Structure — empty and unfiled suites

A `GROUP BY suite` **cannot find empty suites**: a suite with no cases produces
no group. Use the suite listing, which carries `cases_count` per suite:

```
GET /v1/suite/{code}?limit=100
```

Paginate with `offset` until `total` is covered. Flag suites with
`cases_count == 0`, and thin ones (1–2 cases) where siblings have many.

Cases filed nowhere are the mirror-image gap:

```
entity = "case" and project = "CODE" and suite is empty
```

For per-area depth, `suiteTree` matches a suite **and all its descendants**,
which is what you want for "how covered is area X":

```
entity = "case" and project = "CODE" and suiteTree = "tests/api/billing"
```

### 5. Risk weighting — check it is possible first

```
SELECT (priority, COUNT(*)) entity = "case" and project = "CODE" GROUP BY priority
```

Integer codes: 0 = Not set, 1 = High, 2 = Medium, 3 = Low. **`priority` has no
"critical" value** — critical is a *severity*, and `priority = "critical"` fails
outright.

Look at how much is `Not set` before ranking anything by priority. If most cases
have no priority, then "high-priority cases that aren't automated" describes a
handful of outliers, not the real risk — and the honest finding is that the
project has no usable risk metadata. Report that instead of a confident ranking
built on 0.4% of the data.

When priority *is* populated, the risk-weighted gap is:

```
entity = "case" and project = "CODE" and automation = "Manual" and priority = "High"
```

### 6. Freshness

```
entity = "case" and project = "CODE" and updated <= now("-6m")
```

Cases untouched for a long time while the product moved on are a quieter gap
than a missing case — they may pass while testing behaviour that no longer
matters. Report as a count with a couple of examples; don't infer staleness is a
defect without knowing the area.

### 7. Rank and report

Rank by what a gap risks, not by count: an untested area covered by a milestone
in flight outranks a large pile of stale low-priority cases. Say what each gap
means, not just its size.

```
## Coverage Gaps — <PROJECT>
Denominator: <N> cases · <M> suites

### Execution
Never executed: <n> (<x>% of cases, lower bound) · not run in 90d: <n>

### Automation
Manual: <n> · To be automated: <n> · Automated: <n> (<x>% automated)

### Structure
Empty suites: <n> of <M> · thin suites (1-2 cases): <n> · cases with no suite: <n>

### Risk weighting
Priority set on <n> of <N> cases (<x>%). <either the High+Manual gap, or:
"risk ranking isn't meaningful on this project — priority is unset for <x>%">

### Freshness
Not updated in 6 months: <n>

### Requirements
<n> requirements, by status: <breakdown>. Coverage per requirement is **not
measurable** — Qase exposes no link between requirements and cases.

### Top gaps (ranked)
1. <area/lens> — <why it matters> — <the number>
   QQL: <query>

### Recommended next steps
- <e.g. "Draft 6 cases for the empty billing/refunds suite — say the word.">
```

Always show the queries. If any figure came from a page rather than the whole
set, mark it.

### 8. Close gaps (only after approval)

If the user asks for the missing cases:

1. Draft them with clear titles, preconditions, steps, expected results.
2. Ensure the target suite exists. Creating one needs `qase_suite_upsert`, which
   is discoverable — activate it via `qase_discover_tools` first.
3. Create them: `qase_case_upsert` for one, `qase_case_bulk_create` for a batch
   (same case body, one request). Enum fields accept labels (`"High"`).
4. Tag them so a human can review what was generated, and report the IDs.

Never bulk-create dozens of cases without showing a sample and getting a yes.

## Guardrails

- Read-only until the user approves a write.
- Never call a `*_delete` tool. (A hook blocks them anyway.)
- Always report gaps against the denominator, never as bare counts.
- State which lens you used — "coverage" without a stated definition is noise.
- Never present requirement coverage as measured; it isn't available.
- Prefer aggregation over paging. If you paged, say how much you saw.
- Don't infer intent from metadata absence: an unset priority means nobody set
  it, not that the case is unimportant.
