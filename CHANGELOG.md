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
