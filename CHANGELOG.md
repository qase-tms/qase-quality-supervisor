# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.3.1] - 2026-08-21

### Fixed
- **Two skills trusted QQL for automation state, which can be stale.** Found while
  running `analyzing-change-impact` against a live workspace: cases `QTC-22` and
  `QTC-98` read `Automated` through REST, and had since 2026-08-10, but QQL still
  reported them `Manual` eleven days later. The filter is applied faithfully — to a
  copy of the data that lags the case.

  That matters because both skills turn on this exact distinction.
  `analyzing-change-impact` grounds its Regression block only on cases a human still
  has to run, so a stale bucket puts automated coverage back on a manual checklist.
  `finding-coverage-gaps` reports the not-automated buckets *as* the gap, so a lag
  overstates it.

  Both now read `automation` from the live entity rather than deciding from a QQL
  predicate, and the coverage skill labels its automation distribution as a floor
  rather than a measurement, with an instruction to spot-check the `Manual` bucket
  against REST before quoting a percentage.

- **Two neighbouring traps, documented with them**, since both distorted the first
  reading of this data: `case.suite` matches by title, and a project can hold several
  suites with the same name (`suite = "Exports"` returned 11 cases where the suite in
  the tree held 6); and a row query can return the same case twice, inflating `total`
  (a five-element `id` list came back as 8 rows, five distinct). Aggregated queries did
  not show the duplication — `GROUP BY` summed exactly to an independent `COUNT(*)`
  both project-wide and under a filter — so aggregation is preferred for any reported
  number. `isManual` is also flagged as not meaning Manual: alone it returned exactly
  the *To be automated* count.

  `references/qql.md` records each finding with the query and the numbers, so the next
  reader does not rediscover them.

## [0.3.0] - 2026-08-20

### Added
- **`analyzing-change-impact`** — a sixth skill, adapted from the internal
  `impact-analysis` plugin. Diffs the current branch against the default branch,
  traces which surfaces the change actually reaches, and produces a QA-facing report:
  an impact analysis (user-facing, plus the public API only when tracing shows it is
  reached) and a numbered checklist split into Regression — grounded in existing
  **manual / to-be-automated** cases, automated ones excluded — and New. Renders to
  `impact-analysis-<branch>-<date>.html` via `assets/impact-template.html`.

  This is the first skill that reads **code** rather than only Qase, which is also how
  it is routed: a branch or PR is impact, the state of a project is one of the others.

  Four things were changed from the internal original, and each was a bug or a
  mismatch rather than a preference:

  - **It targeted a Qase MCP that no longer exists.** Its `allowed-tools` named
    `list_projects`, `list_suites`, `list_cases`, `get_case`, and `get_suite` — all
    removed when the server consolidated its tool surface, leaving only `qql_search`
    of the six. The coverage step is rewritten against `qase_project_context`,
    `qql_search` (filtering `automation` at query time) and `qase_get`.
  - **It posted to Jira automatically, by design** ("zero extra interaction"), through
    an MCP whose comments cannot be edited or deleted afterwards. Posting is now
    opt-in: the default output is the local HTML file, and a tracker comment happens
    only when the user asks and confirms the ticket.
  - **It required a tracker MCP as a hard precondition** and named tools by their
    claude.ai identifiers, so it could not run in a client that registers them
    differently. Requirements are now optional context: no tracker, no
    `[MISMATCH]` flags, report still produced.
  - **It hardcoded one Qase project** and carried an appendix of internal monolith
    paths and class names. The project is now asked for like every other skill, and
    the appendix is dropped — this repository is public. The generic caller-tracing
    rules it generalised are kept.

### Changed
- `SECURITY.md`: records that this skill reads the local git repository (and that the
  code never leaves the machine), that two skills now write HTML, and that a tracker
  comment is a user-initiated exception to "Qase is the only destination".
- Inventory counts move from 6 to 7 (six skills plus the command the CLI counts under
  `Skills`).

## [0.2.0] - 2026-08-20

### Added
- **`reporting-quality-pulse`** — a fifth skill: a visual HTML report card for a
  Qase project over any period the user names (daily through monthly, sprint, or an
  explicit range), covering execution and pass rate, defect backlog with
  high-severity open called out, new and updated cases, who was active, and a
  heuristic A–D grade. It ships with `assets/pulse-template.html` as the reference
  look.

  It is a period overview, deliberately not a release decision: the pulse describes
  a window and grades it, `assessing-release-readiness` judges a named scope and
  answers go/no-go. The agent's routing states that difference, since the two
  phrasings are easy to confuse.

  It is also **not** part of `/quality-supervisor:quality-report`. That command
  stays a text-only read-only sweep; folding a file-writing visual step into it
  would make every sweep slower and leave a file behind whether or not one was
  wanted.

### Changed
- `SECURITY.md` no longer claims the plugin writes nothing to disk —
  `reporting-quality-pulse` writes its card to the working directory. The document
  now states what that file is, that it stays local, and that the skill asks before
  overwriting; it also records that this skill reads the project user list to name
  who was active, and that those names land in the card.
- Inventory counts in `README.md`, `QUICKSTART.md`, and `scripts/verify-plugin.sh`
  move from 5 to 6 (five skills plus the command the CLI counts under `Skills`).

## [0.1.1] - 2026-08-20

### Added
- **Adoption attribution.** `.mcp.json` now declares
  `X-Qase-Integration: quality-supervisor/<version>`, and the self-run instructions
  set the same value in `QASE_MCP_INTEGRATION`. The Qase MCP server (2.2.2+)
  forwards it as `X-MCP-Integration-Name` / `X-MCP-Integration-Version`, letting
  Qase count which teams use the plugin and on which version.

  What this measures is deliberately narrow: the integration, per team, per version.
  Not which skill ran, not what it concluded, nothing about the project or its test
  data. The marker is a constant string, sent only to Qase, only on API calls the
  client was already making — see [SECURITY.md](SECURITY.md), whose no-telemetry
  claim was rewritten rather than left to cover this by omission.
- `scripts/check-version-sync.sh` asserts that all four copies of the version agree
  — both manifests, the marker in `.mcp.json`, and the README's self-run example.
  Nothing builds the marker from the manifest at runtime (`.mcp.json` cannot
  interpolate the plugin version and Claude Code exposes no variable for it), so a
  release bump would otherwise leave it reporting a stale version indefinitely. The
  failure is silent by nature: a wrong-but-well-formed version passes the MCP
  server's validation exactly as well as a correct one. CI runs it as its own step
  in `validate.yml`, ahead of the toolchain install — it needs only bash and sed,
  and a mismatch should read as a version problem rather than a generic static-check
  failure. `scripts/verify-plugin.sh` also calls it, so local runs and the install
  job stay covered.
- `scripts/set-version.sh <version>` bumps all four copies in one command, refuses a
  non-semver argument, and repairs a repository that has already drifted.
- `.githooks/pre-commit` — opt-in local version-sync check for feedback before the
  push (`git config core.hooksPath .githooks`). See `docs/releasing.md`.
- `tests/test-version-sync.sh` exercises both scripts against throwaway fixture
  repositories, including the case that matters most: a missing marker must fail as
  loudly as a mismatched one, since dropping it stops attribution silently.

## [0.1.0] - 2026-08-18

First release. Nothing before this was tagged, so the sections below cover the
whole path from the initial draft to what ships — including the corrections made
to that draft, which are recorded rather than quietly folded in because most of
them changed what the skills conclude, not just how they read.

### Added
- The plugin itself: the `quality-supervisor` orchestrator agent, the
  `/quality-supervisor:quality-report` command, and four skills —
  `finding-coverage-gaps`, `triaging-test-failures`, `analyzing-test-flakiness`,
  `assessing-release-readiness`.
- Marketplace manifest (`.claude-plugin/marketplace.json`) so the plugin can be
  installed via `/plugin marketplace add` + `/plugin install`, with the plugin
  manifest beside it in `.claude-plugin/` and `.mcp.json`, `agents/`, `commands/`,
  and `skills/` at the repository root.
- `docs/gui-smoke-check.md` — a ten-minute manual check per GUI client, covering
  the three things that behave differently there (install, the OAuth flow,
  command syntax) plus a by-hand confirmation that the delete guard loads.
  Everything else about this plugin is verified through the CLI and CI; the
  hosted OAuth flow in a GUI client is genuinely unverified rather than merely
  untested, since the CLI cannot complete that flow headlessly at all.
- `.github/ISSUE_TEMPLATE/misfire.yml` — a structured report form for internal
  dogfooding. It asks for the prompt **verbatim**, since routing is decided from
  exact wording and a paraphrase usually cannot reproduce a miss, and for the
  shape of the project, since most wrong answers turn out to be the data rather
  than the skill. It also lists the two documented behaviours that look like bugs
  (a skill not firing, numbers disagreeing with the UI on older projects) so they
  don't consume triage time.
- `SECURITY.md` — the data-flow review the publish checklist requires for
  sign-off. States what the plugin can reach, that nothing authenticates as the
  plugin itself, how each write path is gated, and which claims are backed by a
  re-runnable test versus merely asserted. The gaps are listed rather than
  glossed: low-permission token boundaries and GUI clients remain unverified.
- `QUICKSTART.md` — install to first report, and how to read one. Documents what
  a full sweep actually costs — measured at roughly 5 minutes, 56 tool calls and
  $2.80 on a 149-case project with milestones and defects — with the two ways to
  spend less, because a "routine sweep" that quietly costs that much is a
  surprise a dogfooder should not discover from a bill. Leads with the
  Data confidence section, since a gap named there is a gap in the evidence
  rather than a clean result, and with the flaky-versus-regression distinction,
  since acting on the wrong one wastes the work.
- `references/qql.md`: a QQL field/enum/limit reference, verified query by query
  against a live Qase workspace. Shared by the skills so query knowledge lives
  in one place instead of being restated (and drifting) in each one.
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
  the `claude` CLI with the expected component inventory (5 skills — the command
  counts as one — 1 agent, and a registered `PreToolUse` hook, whose two matchers
  are asserted directly against `hooks.json`). `--static-only` skips the install
  phase.
- `.github/workflows/validate.yml`: runs the verification on every push and
  pull request, so a manifest regression, a broken hook, or a leaked
  credential fails CI instead of shipping. Split into a `static` job and an
  `install` job; both block, the CLI's install flow having been confirmed to
  work on GitHub's runners without an authenticated session.
- `LICENSE` (MIT).

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
- "What's blocking the release?" is no longer claimed as a reliable trigger. It
  routes about 40% of the time, and the phrase belongs equally to a pull request
  or a deployment, so widening a description to catch it would hijack unrelated
  questions.
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
  the rewritten skills. The agent's tool list omitted the fact that some Qase
  tools are discoverable and must be activated before use at all. It now also
  carries the cross-cutting rules the skills
  depend on — absent data is not good news, report denominators, route
  consistently-failing tests to triage rather than quarantine — and points at
  `references/qql.md`. The command no longer implies assessing-release-readiness can assess
  a whole project without a scope, and gained a Data confidence section so limits
  travel with the report instead of being dropped from it.
- `finding-coverage-gaps` offers `qase_case_bulk_create` for drafting cases in
  batches, alongside single-case creation.
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
- The core/discoverable tool split was inverted in `agents/quality-supervisor.md`
  and `skills/finding-coverage-gaps/SKILL.md`. Re-checked against the hosted
  server with `qase_discover_tools(activate: false)`: `qase_suite_upsert` and
  `qase_run_upsert` are core, while `qase_case_bulk_create`,
  `qase_milestone_upsert`, and `qase_external_issue_link` are discoverable. The
  consequence ran one way only — a batch draft would have failed as an unknown
  tool, which is the write path a coverage gap ends in. README states the split
  with the date it was verified, since it belongs to the server and can move.
- The documented component inventory said 4 skills, 1 agent, 1 command; the CLI
  prints `Skills (5)` because it counts the `quality-report` command among the
  skills. `QUICKSTART.md` and `docs/gui-smoke-check.md` now expect 5/1/1 and
  explain why, so a dogfooder following the smoke check doesn't file a correct
  install as a defect. `scripts/verify-plugin.sh` already asserted the real
  shape; only the human-facing docs were wrong.
- README's repository layout omitted `references/` and `docs/` — including
  `references/qql.md`, which every skill is instructed to read before composing a
  query.
- Every QQL query in `analyzing-test-flakiness` and `triaging-test-failures` — the previous
  ones failed outright. `result` and `run` have no `created` field, so both
  skills' opening queries errored on every call; `run = <id>` and `case = <id>`
  were rejected too, since those fields match titles, not IDs.
