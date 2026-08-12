# Packaging & Publish-Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the automatable packaging/publish-readiness gaps for the `quality-supervisor` plugin — a missing LICENSE and CHANGELOG, a text-only "never delete" promise, and no repeatable way to catch a broken manifest or a leaked credential before it ships.

**Architecture:** Two static compliance files (LICENSE, CHANGELOG), one enforcement mechanism (a `PreToolUse` hook that hard-blocks any Qase MCP tool call whose name contains `delete`), and one verification mechanism (a local shell script wired into CI) that runs the plugin through the real `claude` CLI — manifest validation, install, and component-inventory inspection — plus a narrow secrets check. All commands below were run against this repo and the live `claude` CLI (v2.1.221) during planning; none require `QASE_API_TOKEN` or any login.

**Tech Stack:** Bash, `jq`, the `claude` CLI (`plugin validate`, `plugin marketplace add/remove`, `plugin install/uninstall`, `plugin details`), GitHub Actions.

## Global Constraints

- Scope is this repo (`qase-quality-supervisor`) only. No changes to the Qase MCP server, no OAuth work (tracked in `qase-mcp-server`/`feat/oauth`).
- No task may require clicking through the Claude Desktop/Cowork GUI. Everything must be verifiable from a terminal.
- License: MIT, copyright Qase (already declared in `plugin.json` and both READMEs — this plan just adds the actual `LICENSE` file).
- The hook must block by tool-name pattern (`mcp__qase__.*delete.*`), not an enumerated list, so it also covers destructive tools the Qase MCP server adds later.
- `scripts/verify-plugin.sh` must not require `QASE_API_TOKEN` and must leave no residue in the developer's global Claude Code config after it finishes (marketplace/plugin state is registered and torn down within the same run).
- Every task ends with a git commit on the current branch. Do not push or open a PR — that stays a separate, explicit step per this repo's workflow rules.

---

### Task 1: Add LICENSE

**Files:**
- Create: `LICENSE`

**Interfaces:**
- Produces: nothing consumed programmatically by later tasks; this just satisfies the license claim already made in `plugin.json` (`"license": "MIT"`) and both READMEs.

- [ ] **Step 1: Write the LICENSE file**

```
MIT License

Copyright (c) 2026 Qase

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Verify the file matches the license already declared elsewhere**

Run: `grep -l "MIT" LICENSE plugin.json README.md 2>/dev/null || grep -rl "MIT" LICENSE .claude-plugin/plugin.json README.md`
Expected: all three files listed (they all mention MIT).

- [ ] **Step 3: Commit**

```bash
git add LICENSE
git commit -m "chore: add MIT LICENSE file"
```

---

### Task 2: Add CHANGELOG.md

**Files:**
- Create: `CHANGELOG.md`

**Interfaces:**
- Consumes: the actual commit history/dates already in the repo (import + flatten happened 2026-08-12).
- Produces: an `## [Unreleased]` section that Tasks 3-5 will each append a bullet to as they land.

- [ ] **Step 1: Write the CHANGELOG**

```markdown
# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `LICENSE` (MIT).

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
```

- [ ] **Step 2: Verify it parses as valid Markdown with the expected sections**

Run: `grep -c "^## " CHANGELOG.md`
Expected: `2` (one `[Unreleased]`, one `[0.1.0]`).

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add CHANGELOG"
```

---

### Task 3: Add the destructive-tool-call deny hook

**Files:**
- Create: `hooks/hooks.json`
- Create: `hooks/deny-destructive.sh`
- Create: `tests/test-deny-destructive.sh`
- Modify: `CHANGELOG.md` (append one line under `[Unreleased]`)

**Interfaces:**
- Consumes: the `PreToolUse` hook stdin contract Claude Code provides — a JSON object on stdin with a `tool_name` field (e.g. `mcp__qase__qase_case_delete`, since the MCP server is named `qase` in `.mcp.json`).
- Produces: `hooks/deny-destructive.sh`, invoked by `hooks/hooks.json`'s `PreToolUse` matcher `mcp__qase__.*delete.*`. Always emits a `deny` decision when invoked (the matcher does the filtering, so the script itself doesn't need to re-check the tool name — but it does echo it back in the reason message). Task 4's `verify-plugin.sh` will assert this hook is registered by checking `claude plugin details` reports `Hooks (1)`.

- [ ] **Step 1: Write the failing test**

Create `tests/test-deny-destructive.sh`:

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/deny-destructive.sh"

output="$(echo '{"tool_name":"mcp__qase__qase_case_delete","tool_input":{"id":123}}' | "$HOOK")"

decision="$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision')"
reason="$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')"

if [ "$decision" != "deny" ]; then
  echo "FAIL: permissionDecision was '$decision', expected 'deny'"
  exit 1
fi
if [[ "$reason" != *"mcp__qase__qase_case_delete"* ]]; then
  echo "FAIL: reason did not mention the blocked tool: $reason"
  exit 1
fi

echo "PASS: deny-destructive.sh blocks mcp__qase__qase_case_delete"
```

Then: `chmod +x tests/test-deny-destructive.sh`

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-deny-destructive.sh`
Expected: FAIL — `hooks/deny-destructive.sh: No such file or directory` (the hook script doesn't exist yet).

- [ ] **Step 3: Write the hook script**

Create `hooks/deny-destructive.sh`:

```bash
#!/bin/bash
set -euo pipefail

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name')"

jq -n --arg tool "$tool_name" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Destructive tools are disabled in Quality Supervisor — skills never delete Qase data. Blocked call to " + $tool + ".")
  }
}'
exit 0
```

Then: `chmod +x hooks/deny-destructive.sh`

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-deny-destructive.sh`
Expected: `PASS: deny-destructive.sh blocks mcp__qase__qase_case_delete`

- [ ] **Step 5: Wire the hook into hooks.json**

Create `hooks/hooks.json`:

```json
{
  "description": "Blocks any Qase MCP tool call that could delete data — enforces the plugin's non-destructive design principle technically, not just in prompt text.",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__qase__.*delete.*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/deny-destructive.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 6: Validate the plugin manifest (including the new hooks.json) with the strict validator**

Run: `claude plugin validate .claude-plugin/plugin.json --strict`
Expected: `✔ Validation passed` (this call validates the plugin manifest AND the sibling `hooks/hooks.json` — confirmed during planning that pointing `validate` at `.claude-plugin/plugin.json` also reports a `Validating hooks: .../hooks/hooks.json` section and fails if the hook config doesn't match the schema).

- [ ] **Step 7: Append to CHANGELOG.md**

Under `## [Unreleased]` → `### Added`, add:

```markdown
- `hooks/hooks.json` + `hooks/deny-destructive.sh`: a `PreToolUse` hook that
  blocks any `mcp__qase__*delete*` tool call, so "skills never delete Qase
  data" is enforced technically, not only in skill prompt text.
```

- [ ] **Step 8: Commit**

```bash
git add hooks/hooks.json hooks/deny-destructive.sh tests/test-deny-destructive.sh CHANGELOG.md
git commit -m "feat: add PreToolUse hook blocking destructive Qase MCP tool calls"
```

---

### Task 4: Add the local verification script

**Files:**
- Create: `scripts/verify-plugin.sh`
- Modify: `CHANGELOG.md` (append one line under `[Unreleased]`)

**Interfaces:**
- Consumes: `claude` CLI subcommands `plugin validate`, `plugin marketplace add/remove`, `plugin install/uninstall`, `plugin details` (all confirmed during planning to run without `QASE_API_TOKEN` or any login); the marketplace name `quality-supervisor` and plugin id `quality-supervisor@quality-supervisor` as declared in `.claude-plugin/marketplace.json`.
- Produces: a script with a single meaningful exit code — `0` if the manifest, hooks, component inventory, and secrets scan all pass; non-zero (with a printed reason) otherwise. Task 5's CI workflow calls this script directly.

- [ ] **Step 1: Write the script**

Create `scripts/verify-plugin.sh`:

```bash
#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Validating marketplace manifest"
claude plugin validate . --strict

echo "==> Validating plugin manifest + hooks"
claude plugin validate .claude-plugin/plugin.json --strict

echo "==> Secrets scan (literal QASE_API_TOKEN values in JSON files)"
if grep -rnE '"QASE_API_TOKEN"[[:space:]]*:[[:space:]]*"[^$][^"]{9,}"' --include='*.json' .; then
  echo "FAIL: a JSON file appears to contain a literal QASE_API_TOKEN value instead of \${QASE_API_TOKEN}. See match above." >&2
  exit 1
fi
echo "no literal token found"

echo "==> Installing the plugin from this repo as a local marketplace"
claude plugin marketplace add "$REPO_ROOT" >/dev/null
cleanup() {
  claude plugin uninstall quality-supervisor@quality-supervisor -y >/dev/null 2>&1 || true
  claude plugin marketplace remove quality-supervisor >/dev/null 2>&1 || true
}
trap cleanup EXIT

claude plugin install quality-supervisor@quality-supervisor >/dev/null

echo "==> Checking component inventory"
details="$(claude plugin details quality-supervisor)"
echo "$details"

if ! echo "$details" | grep -qE 'Skills \(5\)'; then
  echo "FAIL: expected 5 skills (coverage-gap-analysis, failure-triage, flakiness-stability, release-readiness, quality-report), got:" >&2
  echo "$details" | grep 'Skills' >&2
  exit 1
fi
if ! echo "$details" | grep -qE 'Agents \(1\)'; then
  echo "FAIL: expected 1 agent (quality-supervisor)." >&2
  exit 1
fi
if ! echo "$details" | grep -qE 'Hooks \(1\)'; then
  echo "FAIL: expected 1 hook (the destructive-call deny guard)." >&2
  exit 1
fi

echo "==> All checks passed"
```

Then: `chmod +x scripts/verify-plugin.sh`

Note on the assertions: `claude plugin details` (v2.1.221) reports the `/quality-report` command together with the four skills under a single `Skills (N)` count — there is no separate "Commands" row in its output. This was confirmed by running `claude plugin install` + `claude plugin details` against this exact repo during planning, which printed `Skills (5)  coverage-gap-analysis, failure-triage, flakiness-stability, quality-report, release-readiness` and `Agents (1)  quality-supervisor`. The script asserts against that verified real output shape, not against the spec's earlier "4 skills + 1 command" phrasing.

- [ ] **Step 2: Run it and confirm it passes end-to-end**

Run: `bash scripts/verify-plugin.sh`
Expected: ends with `==> All checks passed` and exit code `0`. This step registers a local marketplace and installs the plugin into your global Claude Code config, then removes both in the `cleanup` trap before the script exits — confirm with `claude plugin list` afterward that `quality-supervisor` is no longer listed.

- [ ] **Step 3: Confirm the failure path works**

Temporarily move `skills/failure-triage` **out of the repo tree** (e.g. `mv skills/failure-triage /tmp/failure-triage-temp`), rerun `bash scripts/verify-plugin.sh`, and confirm it fails with the `FAIL: expected 5 skills` message and a non-zero exit code. Then move it back and rerun to confirm it passes again.

Two gotchas, both confirmed by running this during implementation:
- Renaming the directory in place (e.g. to `skills/failure-triage.bak`) does **not** trigger the failure — the CLI discovers skills by finding `SKILL.md` files, not by directory name, so a renamed directory still counts toward `Skills (5)`. The directory must leave the tree.
- Check the exit code with `bash scripts/verify-plugin.sh; echo $?` — do **not** pipe the script to `tail`/`head` first, or `$?` reports the pager's exit code (0) instead of the script's.

- [ ] **Step 4: Append to CHANGELOG.md**

Under `## [Unreleased]` → `### Added`, add:

```markdown
- `scripts/verify-plugin.sh`: validates the marketplace and plugin
  manifests (including hooks), scans for a literal `QASE_API_TOKEN` value
  committed to a JSON file, and confirms the plugin installs via the
  `claude` CLI with the expected component inventory (5 skills, 1 agent, 1
  hook).
```

- [ ] **Step 5: Commit**

```bash
git add scripts/verify-plugin.sh CHANGELOG.md
git commit -m "test: add local plugin verification script"
```

---

### Task 5: Add the CI workflow

**Files:**
- Create: `.github/workflows/validate.yml`
- Modify: `CHANGELOG.md` (append one line under `[Unreleased]`)

**Interfaces:**
- Consumes: `scripts/verify-plugin.sh` from Task 4 (called as-is, no arguments).
- Produces: a GitHub Actions check that runs on every push and pull request; a non-zero exit from `verify-plugin.sh` fails the check and blocks merge (per branch protection, if/when configured — not part of this plan).

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/validate.yml`:

```yaml
name: Validate plugin

on:
  push:
  pull_request:

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install claude CLI
        run: npm install -g @anthropic-ai/claude-code

      - name: Run plugin verification
        run: bash scripts/verify-plugin.sh
```

- [ ] **Step 2: Validate the workflow YAML syntax locally**

Run: `python3 -c "import yaml, sys; yaml.safe_load(open('.github/workflows/validate.yml'))" && echo "valid YAML"`
Expected: `valid YAML`

(If `python3`/`pyyaml` isn't available, an equivalent check is fine — e.g. `ruby -ryaml -e "YAML.load_file('.github/workflows/validate.yml')" && echo valid`. Either way, this step must actually parse the file, not just eyeball it.)

- [ ] **Step 3: Append to CHANGELOG.md**

Under `## [Unreleased]` → `### Added`, add:

```markdown
- `.github/workflows/validate.yml`: runs `scripts/verify-plugin.sh` on every
  push and pull request, so a manifest regression or a leaked credential
  fails CI instead of shipping.
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/validate.yml CHANGELOG.md
git commit -m "ci: run plugin verification on push and pull request"
```

---

## Follow-ups explicitly not in this plan (per spec)

- Confirming the CI workflow actually goes green on GitHub's runners (this plan validates the YAML locally and validates that the underlying commands work on this machine; the first real push is the true end-to-end confirmation).
- Manual install-and-run check in the real Claude Desktop/Cowork GUI.
- The "Quality Supervisor" naming/trademark check.
- Tagging a release (`claude plugin tag`) — a release action, left as a deliberate follow-up step for whoever decides it's time to cut `0.1.0` as an actual git tag, not automated here.
