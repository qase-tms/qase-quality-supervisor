# Quality Supervisor — Packaging & Publish-Readiness Design

## Context

The [Quality Supervisor PRD](https://drive.google.com/file/d/1vut_HFDzBGbIbHkXCzQB0CvYj8r-Q01u/view) describes four workstreams for publishing the plugin (MCP endpoint,
packaging & distribution, security & compliance, onboarding & docs) plus a
five-layer testing approach. This spec covers only the first slice of that
work, scoped down through a brainstorming session on 2026-08-12.

## Scope

**In scope:** automatable, plugin-repo-only work that closes the concrete
gaps found in `qase-quality-supervisor`'s current packaging/publish-readiness
posture — the parts of the PRD's Workstream A ("Packaging & distribution")
and the plugin-side slice of Workstream B ("Security, privacy & compliance")
that can be built and verified from this repo without a GUI.

**Out of scope for this spec** (tracked elsewhere or left as manual
follow-up, not because they don't matter):
- The hosted, OAuth-authenticated Qase MCP endpoint. That work lives in
  `qase-mcp-server` on the `feat/oauth` branch and is tracked there.
- Manual install verification by clicking through the real Claude
  Desktop/Cowork GUI.
- The "Discoverability & naming" trademark/registry check on "Quality
  Supervisor" — a legal determination, not a code change.
- Whether an Anthropic plugin-directory submission process exists — research
  to do closer to launch, not a repo artifact.
- Correctness/testing of the four skills themselves (coverage-gap-analysis,
  failure-triage, flakiness-stability, release-readiness) and the eval
  harness for skill triggering — a separate "Testing & eval harness"
  sub-project.
- Onboarding docs content (quickstart, per-skill guides, demo) — a separate
  "Onboarding/docs" sub-project, sequenced after this one and after testing,
  since docs should describe already-verified behavior.

## Goals

- Close two concrete items from the PRD's publish-readiness checklist
  (§8.5): "Manifest validated, semver + CHANGELOG" (fully), and the
  CLI-verifiable slice of "Marketplace repo public + install verified"
  (install via the `claude` CLI; the Desktop/Cowork GUI check stays manual
  and out of scope here).
- Turn the plugin's "no skill calls `*_delete`" design principle — currently
  only a promise in skill/agent prompt text — into a technically enforced
  guarantee.
- Make manifest/install validation and a basic secrets check a standing CI
  gate instead of a one-off manual run, so a later edit to `plugin.json` or
  the skill files can't silently break the package or leak a credential.

## Components / deliverables

1. **`LICENSE`** — MIT license text, copyright Qase. Closes the gap where
   `plugin.json` and both READMEs already declare "MIT" but no license file
   exists in the repo.
2. **`CHANGELOG.md`** — Keep a Changelog format. First entry documents
   `0.1.0`: the plugin draft import and the flattening of the repo structure
   to a single-plugin layout.
3. **`hooks/hooks.json`** + a deny script — a `PreToolUse` hook matching any
   Qase MCP tool call whose name contains `delete` (tool names surface to
   Claude Code as `mcp__qase__<tool>` given the server is named `qase` in
   `.mcp.json`; the matcher is the pattern `mcp__qase__.*delete.*` rather
   than an enumerated list, so it also covers any destructive tool the MCP
   server adds later). On a match, the hook blocks the call and returns a
   short reason to the model (e.g. "Destructive tools are disabled in
   Quality Supervisor — skills never delete Qase data") so the agent can
   recover mid-conversation instead of dead-ending silently.
4. **`scripts/verify-plugin.sh`** — local verification script:
   1. `claude plugin marketplace add .` — register this repo as a local
      marketplace.
   2. `claude plugin install quality-supervisor@quality-supervisor` —
      install the plugin from it.
   3. `claude plugin details quality-supervisor` — assert the output lists
      exactly 4 skills + 1 agent + 1 command; a mismatch means the manifest
      or a directory-naming convention broke, and the script exits non-zero
      with the actual component list printed.
   4. A secrets grep across the repo (looking for token-shaped strings, not
      just the `${QASE_API_TOKEN}` placeholder) to catch an accidentally
      committed real credential; on a match, exit non-zero and print the
      file/line, never the matched value.
   5. Cleanup: uninstall the plugin, then remove the marketplace
      registration, so repeated local runs don't accumulate state in a
      developer's global Claude Code config, and so the script is safe to
      run more than once.
5. **`.github/workflows/validate.yml`** — CI workflow triggered on push and
   pull request, running the same verification. A red run blocks merge —
   the same "regression gate" philosophy the PRD applies to the skill test
   suites (§9), just applied to packaging.

## Mechanics

- The hook intercepts tool-call requests before they reach the Qase MCP
  server; it is a pure request-side block inside Claude Code and never talks
  to Qase itself.
- `verify-plugin.sh` operates entirely against local Claude Code state
  (marketplace registrations, the installed-plugin list) and this repo's own
  files. It does not call the live Qase API or MCP server and does not
  require a `QASE_API_TOKEN` to run.

## Error handling

- Component-count mismatch in `plugin details` → non-zero exit, actual
  component list printed, so a manifest/path regression is caught
  immediately instead of shipping silently.
- Secrets-grep match → non-zero exit, file/line printed (not the secret
  value), so CI logs don't become a second leak.
- Hook deny → short actionable reason returned to the model, not a bare
  failure.

## Testing

- `verify-plugin.sh`, run both locally and in CI, is the test for this
  workstream — there's no separate framework needed for validating static
  files (license, changelog, manifest, hook config).
- Explicitly not covered here (see Scope): real Desktop/Cowork GUI
  click-through, and the naming/trademark legal check.

## Open questions / risks for the implementation plan

- **CI feasibility of the full install flow is unverified.** Whether
  `claude plugin marketplace add` / `install` / `details` work
  non-interactively in a headless CI runner (no logged-in Claude Code
  session) has not been checked. If they require interactive auth, the CI
  workflow falls back to static JSON-schema validation of `plugin.json` /
  `marketplace.json` plus the secrets scan, and the full
  install-through-`details` check stays a local-only script run by
  developers before pushing. This must be confirmed early in implementation
  since it determines the actual shape of `validate.yml`.
- **The hook matcher assumes the MCP server keeps the name `qase`** as
  configured in `.mcp.json` today. If that server name ever changes, the
  hook's matcher pattern must be updated in lockstep or it silently stops
  protecting anything.
