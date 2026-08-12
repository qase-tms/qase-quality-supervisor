# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `LICENSE` (MIT).
- `hooks/hooks.json` + `hooks/deny-destructive.sh`: a `PreToolUse` hook that
  blocks any `mcp__qase__*delete*` tool call, so "skills never delete Qase
  data" is enforced technically, not only in skill prompt text.
- `scripts/verify-plugin.sh`: validates the marketplace and plugin
  manifests (including hooks), scans for a literal `QASE_API_TOKEN` value
  committed to a JSON file, and confirms the plugin installs via the
  `claude` CLI with the expected component inventory (5 skills, 1 agent, 1
  hook).

## [0.1.0] - 2026-08-12

### Added
- Initial Quality Supervisor plugin draft: the `quality-supervisor`
  orchestrator agent, the `/quality-report` command, and four skills —
  `coverage-gap-analysis`, `failure-triage`, `flakiness-stability`,
  `release-readiness`.
- Marketplace manifest (`.claude-plugin/marketplace.json`) so the plugin can
  be installed via `/plugin marketplace add` + `/plugin install`.
- Flattened the repo to a single-plugin layout: `plugin.json`, `.mcp.json`,
  `agents/`, `commands/`, and `skills/` live at the repo root next to
  `.claude-plugin/marketplace.json`, with the marketplace entry's `source`
  set to `"."`.
