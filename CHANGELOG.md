# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `LICENSE` (MIT).
- `hooks/hooks.json` + `hooks/deny-destructive.sh` +
  `hooks/deny-destructive-api.sh`: `PreToolUse` hooks that block any
  `mcp__qase__*delete*` tool call and any `qase_api` call whose method is
  `DELETE`, so "skills never delete Qase data" is enforced technically, not
  only in skill prompt text. Both hooks are fail-closed (they block on
  internal error) and depend on no external JSON tooling.
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
  credential fails CI instead of shipping. Split into a blocking `static`
  job and a non-blocking `install` job, the latter until the CLI's install
  flow is observed working on headless runners.

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
