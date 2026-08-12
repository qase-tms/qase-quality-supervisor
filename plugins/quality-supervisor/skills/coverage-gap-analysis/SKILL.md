---
name: coverage-gap-analysis
description: >-
  Find untested or under-tested areas of a Qase project and turn them into
  ready-to-review test cases. Use when the user asks about test coverage,
  coverage gaps, "what isn't tested," untested requirements/features,
  missing test cases, cases without automation, or wants to generate cases
  to close a gap. Part of the Quality Supervisor plugin; powered by the Qase
  MCP server.
---

# Quality Supervisor — Coverage / Gap Analysis

Identify where a Qase project lacks test coverage — untested requirements,
suites with thin or no cases, un-automated critical paths, stories shipped
without tests — and (on request) draft the missing cases for human review.

Qase stays the system of record. This skill **reads** to find gaps and only
**writes** new/updated cases after the user confirms.

## When to use
- "Where are our coverage gaps?" / "What isn't tested in project ABC?"
- "Which requirements/user stories have no linked test cases?"
- "Which suites are thin or empty?" / "What critical cases aren't automated?"
- "Generate the missing test cases for <feature/requirement>."

## Prerequisites
- Qase MCP server connected and authenticated.
- A target **project code** (e.g. `DEMO`). If the user hasn't given one, ask,
  or infer it from context. Never guess silently.

## Tools this skill uses
- `qase_project_context` — one call for project details, suites tree,
  milestones, environments, custom fields, users. **Always call first.**
- `qql_search` — the analytical workhorse; query cases, requirements, results.
- `qase_get` — fetch a specific entity (requirement, case, suite) with `fields`
  projection when you need detail.
- `qql_help` — confirm QQL syntax/fields if a query is rejected.
- `qase_discover_tools` — activate any non-core tool you need (`query:"..."`).
- `qase_case_upsert` — create/update cases to close gaps (write step).
- `qase_suite_upsert` — create a suite to hold new cases if needed.
- `qase_api` — escape hatch (`/v1/...`) for anything a dedicated tool misses,
  e.g. requirement→case coverage links.

## Workflow

### 1. Seed context
Call `qase_project_context` with the project code. Note the suites tree,
custom fields (esp. anything like "Requirement", "Component", "Layer"), and
whether requirements are in use.

### 2. Establish the coverage denominator
Decide what "should be tested." Pick the lens the user wants:
- **Requirements lens** — every requirement should have ≥1 linked case.
  ```
  entity = "requirement" and project = "DEMO"
  ```
  Then for each requirement, check for linked cases. If QQL doesn't expose the
  link directly, use `qase_get` on the requirement or `qase_api`
  (`GET /v1/requirement/...`) to read coverage.
- **Suite/structure lens** — every functional suite should hold cases.
  Walk the suites tree from `qase_project_context`; flag suites with 0 cases:
  ```
  entity = "case" and project = "DEMO" and suite = <suiteId>
  ```
- **Recent-delivery lens** — anything created/updated recently but untested,
  using `now()`:
  ```
  entity = "case" and project = "DEMO" and created >= now("-30d")
  ```

### 3. Find the gaps
Run targeted QQL. Confirm field names with `qql_help` if a query errors — QQL
field values are case-sensitive; `~` is case-insensitive substring:
- Cases with **no automation** (automation gap):
  ```
  entity = "case" and project = "DEMO" and automation = "Not automated"
  ```
- **High-priority** cases that are not automated (risk-weighted gap):
  ```
  entity = "case" and project = "DEMO" and priority in ("high","critical") and automation = "Not automated"
  ```
- Cases **never executed** or with no recent result — cross-reference
  `entity = "result"` for the project and diff against the case list.
- Requirements with **no coverage** — list requirements, then subtract those
  that have linked cases.

### 4. Rank by risk
Don't dump a flat list. Rank gaps by: priority/severity of the area, whether
it's on a milestone or release, recency of related code/requirement changes,
and blast radius. Present the top gaps first.

### 5. Report
Output a concise, skimmable summary (see format below). Always show your QQL so
the user can reproduce it.

### 6. Close gaps (only on confirmation)
If the user says "generate the missing cases":
1. Draft cases with clear titles, preconditions, steps, expected results.
2. Ensure the target suite exists (`qase_suite_upsert` if needed).
3. Create with `qase_case_upsert` (enum fields accept labels like `"high"`).
   Keep titles unique.
4. Tag AI-drafted cases (label or `cf[...]`) so humans can review, and report
   exactly what was created with IDs.
Never bulk-create dozens of cases without showing a sample and getting a yes.

## Output format
```
## Coverage Gap Report — <PROJECT> (<date>)
Lens: <requirements | suite | recent delivery>
Denominator: <N requirements / N suites / N cases considered>

### Top gaps (risk-ranked)
1. <Area/Requirement> — <why it matters> — <gap: 0 cases | not automated | never run>
   QQL: <query>
2. ...

### Summary
- Untested requirements: N
- Empty/thin suites: N
- High-priority cases without automation: N

### Recommended next steps
- <e.g. "Draft 6 cases for REQ-14 checkout flow — say the word.">
```

## Guardrails
- Read-only until the user approves writes. Confirm before any `*_upsert`.
- Never call `*_delete` tools in this skill.
- State assumptions (which lens, what "covered" means) explicitly.
- If a QQL field is unknown, call `qql_help` rather than guessing.
- Keep Qase as source of truth; the LLM drafts, humans approve.
