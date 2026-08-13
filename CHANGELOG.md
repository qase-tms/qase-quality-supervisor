# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `references/qql.md`: a QQL field/enum/limit reference, verified query by query
  against a live Qase workspace. Shared by the skills so query knowledge lives
  in one place instead of being restated (and drifting) in each one.
- `LICENSE` (MIT).

### Changed
- `flakiness-stability` rewritten around what QQL can actually do. It now
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

- `failure-triage` rewritten. It takes a run's failure counts from the run's own
  `stats` block instead of counting fetched rows, and fetches the failing
  results through the REST API because QQL cannot scope results to a run ID —
  its `run` field matches the run title, and autotest titles repeat, so the old
  approach could silently mix in other runs. It reads `filtered` rather than
  `total` when filtering (the latter ignores filters), cross-checks the two
  sources, distinguishes never-executed tests from failures, and no longer
  claims defects are linked to results — `qase_triage_defect` reports a link
  count it does not act on, and the API has no defect-side way to attach
  results, so the evidence goes into the defect body instead.

### Fixed
- Every QQL query in `flakiness-stability` and `failure-triage` — the previous
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
  `coverage-gap-analysis`, `failure-triage`, `flakiness-stability`,
  `release-readiness`.
- Marketplace manifest (`.claude-plugin/marketplace.json`) so the plugin can
  be installed via `/plugin marketplace add` + `/plugin install`.
- Flattened the repo to a single-plugin layout: `plugin.json` sits in
  `.claude-plugin/` alongside `marketplace.json`, while `.mcp.json`,
  `agents/`, `commands/`, and `skills/` live at the repo root, with the
  marketplace entry's `source` set to `"."`.
