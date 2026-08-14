# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `SECURITY.md` — the data-flow review the publish checklist requires for
  sign-off. States what the plugin can reach, that nothing authenticates as the
  plugin itself, how each write path is gated, and which claims are backed by a
  re-runnable test versus merely asserted. The gaps are listed rather than
  glossed: low-permission token boundaries and GUI clients remain unverified.
- `QUICKSTART.md` — install to first report, and how to read one. Leads with the
  Data confidence section, since a gap named there is a gap in the evidence
  rather than a clean result, and with the flaky-versus-regression distinction,
  since acting on the wrong one wastes the work.

### Changed
- Skills renamed to the gerund form the authoring guide prefers:
  `analyzing-test-flakiness`, `triaging-test-failures`, `finding-coverage-gaps`,
  `assessing-release-readiness`. The names keep their trigger vocabulary, since
  `name` is loaded alongside `description` and participates in routing —
  measured at 90.0% after the rename against 92.2% before, a difference inside
  the 88–95% band a single pass produces, so routing is unaffected.
- `references/qql.md` opens with a table of contents. It is 238 lines, and a
  reference that long can be previewed with a partial read — without contents,
  the second half was invisible, including the section on QQL and REST
  disagreeing about defect counts, which is what keeps the release gate from
  producing a false GO.
- `assessing-release-readiness` carries a progress checklist for its seven
  steps. A silently skipped dimension produces a verdict that looks complete
  and isn't, which is the failure that skill exists to prevent.
- The eval suite gained a `domain-neutral` case kind. "What's blocking the
  release?" routes about 40% of the time and cannot be claimed reliably — the
  phrase belongs equally to a pull request or a deployment, so widening a
  description to catch it would hijack unrelated questions. It stays visible in
  the suite without counting against recall.

### Added
- `references/qql.md`: a QQL field/enum/limit reference, verified query by query
  against a live Qase workspace. Shared by the skills so query knowledge lives
  in one place instead of being restated (and drifting) in each one.
- `LICENSE` (MIT).

### Changed
- `analyzing-test-flakiness` rewritten around what QQL can actually do. It now
  distinguishes genuinely flaky cases (both passes and failures in the window)
  from consistently failing ones (a regression, needing the opposite response) —
  on a real project, most high-failure cases turn out to be the latter, so the
  previous failure-count approach misreported them. Detection uses server-side
  `GROUP BY` aggregation instead of paging through result rows, checks that the
  time window contains data before concluding anything, treats Qase's `isFlaky`
  flag as a cross-check rather than a shortcut, and writes findings back via the
  native `is_flaky` field. Claims the data cannot support (result ordering,
  per-environment breakdowns, confirming flakiness by re-running) are now stated
  as limits instead of promised.

- `triaging-test-failures` rewritten. It takes a run's failure counts from the run's own
  `stats` block instead of counting fetched rows, and fetches the failing
  results through the REST API because QQL cannot scope results to a run ID —
  its `run` field matches the run title, and autotest titles repeat, so the old
  approach could silently mix in other runs. It reads `filtered` rather than
  `total` when filtering (the latter ignores filters), cross-checks the two
  sources, distinguishes never-executed tests from failures, and no longer
  claims defects are linked to results — `qase_triage_defect` reports a link
  count it does not act on, and the API has no defect-side way to attach
  results, so the evidence goes into the defect body instead.

- `quality-supervisor` agent and `/quality-report` command brought in line with
  the rewritten skills. The agent's tool list claimed `qase_run_upsert` as core
  when it is discoverable, and omitted `qase_case_bulk_create`,
  `qase_external_issue_link`, and the fact that discoverable tools need
  activating at all. It now also carries the cross-cutting rules the skills
  depend on — absent data is not good news, report denominators, route
  consistently-failing tests to triage rather than quarantine — and points at
  `references/qql.md`. The command no longer implies assessing-release-readiness can assess
  a whole project without a scope, and gained a Data confidence section so limits
  travel with the report instead of being dropped from it.
- `finding-coverage-gaps`: `qase_suite_upsert` is a discoverable tool, so the
  skill now says to activate it via `qase_discover_tools` first, and offers
  `qase_case_bulk_create` for drafting cases in batches.
- `assessing-release-readiness` rewritten. Scope is resolved by milestone, plan, or run
  title rather than ID — the old `milestone = <id>` and `run in (<ids>)` forms
  were rejected outright — and results are no longer scoped by milestone, since
  `result.milestone` is inherited from the case, not the run, and returns nothing
  on the common setup where runs carry the milestone but cases don't. Execution
  progress and pass rate come from each run's own `stats`, with `untested`
  reported alongside the pass rate: a run where nothing executed has no failures
  and previously read as green. The defect dimension now checks whether the
  project tracks defects at all before reporting "no blockers", and a new
  INSUFFICIENT EVIDENCE verdict covers empty scopes and incomplete execution
  instead of guessing. Decisive numbers are cross-checked against REST, because
  the two sources disagree — on one project QQL returned a run as live that REST
  reported as not found, and their run totals differed twofold.
- `finding-coverage-gaps` rewritten. Its requirements lens was unimplementable —
  Qase exposes no link between a requirement and its cases in either direction,
  and the REST endpoint the skill fell back to does not exist — so the skill now
  reports requirement coverage as unavailable, while still counting requirements
  by status and type. Execution coverage is derived by comparing the case total
  against the number of distinct cases with results, which yields the
  never-executed count in two queries instead of paging two full lists. Empty
  suites come from the suite listing's `cases_count`, since a `GROUP BY suite`
  structurally cannot show a suite that has no cases. Risk weighting now checks
  whether priority is populated at all before ranking by it, because on a project
  where nearly every case is "Not set" the old ranking described a handful of
  outliers as the risk picture.
- `.mcp.json` now points at the hosted, OAuth-authenticated endpoint
  (`https://mcp.qase.io/mcp`) instead of launching the server via `npx`, so
  installing the plugin no longer involves creating or storing an API token. The
  local token-based configuration is documented in the README for Business plans
  and development, since the hosted endpoint requires Enterprise.
- Skills now assume MCP server **2.1.1**, which fixed the invalid QQL example in
  the tool schema, the silent truncation in `qase_project_context`, and
  `qase_triage_defect`'s dead link parameters. The guidance those defects
  required has been removed; the remaining constraint — that Qase has no
  defect-side way to attach results — is a property of the API, not the server,
  and stays documented.
- `references/qql.md`: query limit updated to 2,000 characters (2.1.0 raised it
  from 1,000) and ID batches sized accordingly. Server 2.1.1 corrected
  `qql_help`'s aggregation examples, which had placed `SELECT` after the
  conditions where the API rejects it, so the warning about that is gone; the
  QQL-versus-REST data divergence is unaffected by either release and stays
  documented.

### Fixed
- Every QQL query in `analyzing-test-flakiness` and `triaging-test-failures` — the previous
  ones failed outright. `result` and `run` have no `created` field, so both
  skills' opening queries errored on every call; `run = <id>` and `case = <id>`
  were rejected too, since those fields match titles, not IDs.
- `hooks/hooks.json` + `hooks/deny-destructive.sh` +
  `hooks/deny-destructive-api.sh`: `PreToolUse` hooks that block any
  `mcp__qase__*delete*` tool call and any `qase_api` call whose method is
  `DELETE`, so "skills never delete Qase data" is enforced technically, not
  only in skill prompt text. Both hooks are fail-closed — they block rather
  than allow when anything unexpected happens — and need no JSON tooling. The
  `qase_api` guard errs deliberately toward denial: it blocks on any
  `"method": "delete"` in the payload rather than trying to resolve
  `tool_input.method` without a parser, so a nested or decoy field can only
  cause a needless denial, never a missed deletion.
- `tests/test-deny-destructive.sh`: covers both hooks, including that they
  fail closed rather than fail open when their environment is broken.
- `scripts/verify-plugin.sh`: validates the marketplace and plugin manifests
  (including hooks), checks the compliance files exist, scans for a literal
  `QASE_API_TOKEN` value committed to a JSON file (reporting location only,
  never the value), runs the hook tests, and confirms the plugin installs via
  the `claude` CLI with the expected component inventory (5 skills, 1 agent,
  2 hooks). `--static-only` skips the install phase.
- `.github/workflows/validate.yml`: runs the verification on every push and
  pull request, so a manifest regression, a broken hook, or a leaked
  credential fails CI instead of shipping. Split into a `static` job and an
  `install` job; both block, the CLI's install flow having been confirmed to
  work on GitHub's runners without an authenticated session.

## [0.1.0] - 2026-08-12

### Added
- Initial Quality Supervisor plugin draft: the `quality-supervisor`
  orchestrator agent, the `/quality-report` command, and four skills —
  `finding-coverage-gaps`, `triaging-test-failures`, `analyzing-test-flakiness`,
  `assessing-release-readiness`.
- Marketplace manifest (`.claude-plugin/marketplace.json`) so the plugin can
  be installed via `/plugin marketplace add` + `/plugin install`.
- Flattened the repo to a single-plugin layout: `plugin.json` sits in
  `.claude-plugin/` alongside `marketplace.json`, while `.mcp.json`,
  `agents/`, `commands/`, and `skills/` live at the repo root, with the
  marketplace entry's `source` set to `"."`.
