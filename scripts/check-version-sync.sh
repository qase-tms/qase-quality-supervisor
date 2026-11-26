#!/bin/bash
#
# Asserts that every place carrying this plugin's version agrees with
# .claude-plugin/plugin.json, which is the single source of truth.
#
# Three manifests repeat the version, because none of them can read the others,
# the OpenAI plugin directory package carries a fourth, and the Cursor manifest
# a fifth.
#
# Called by scripts/verify-plugin.sh (so CI enforces it on every push) and by
# .githooks/pre-commit (so a release bump is caught before the push). Both share
# this file rather than reimplementing the comparison.
#
# Usage: check-version-sync.sh [repo-root]   (defaults to this repo)

set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$REPO_ROOT"


fail() {
  echo "FAIL: $1" >&2
  echo "      Run scripts/set-version.sh <version> to update every place at once." >&2
  exit 1
}

plugin_version="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' .claude-plugin/plugin.json | head -1)"
[ -n "$plugin_version" ] || fail "could not read \"version\" from .claude-plugin/plugin.json."

# The marketplace manifest carries its own copy, and a marketplace whose version
# trails the plugin's misreports what installers are offered.
marketplace_version="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' .claude-plugin/marketplace.json | head -1)"
[ -n "$marketplace_version" ] || fail "could not read \"version\" from .claude-plugin/marketplace.json."
if [ "$marketplace_version" != "$plugin_version" ]; then
  fail ".claude-plugin/marketplace.json is version ${marketplace_version}, but .claude-plugin/plugin.json is ${plugin_version}."
fi

# The Codex manifest is a second plugin manifest for a second harness. A stale
# version here misreports which release a Codex user is running, and the two
# manifests are never read by the same tool, so nothing else would notice.
codex_version="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' .codex-plugin/plugin.json | head -1)"
[ -n "$codex_version" ] || fail "could not read \"version\" from .codex-plugin/plugin.json."
if [ "$codex_version" != "$plugin_version" ]; then
  fail ".codex-plugin/plugin.json is version ${codex_version}, but .claude-plugin/plugin.json is ${plugin_version}."
fi

# The OpenAI directory refuses a new upload whose version did not change, and a
# package that trails the plugin would describe an older release.
openai_version="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' openai/plugin.json | head -1)"
[ -n "$openai_version" ] || fail "could not read \"version\" from openai/plugin.json."
if [ "$openai_version" != "$plugin_version" ]; then
  fail "openai/plugin.json is version ${openai_version}, but .claude-plugin/plugin.json is ${plugin_version}."
fi

cursor_version="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' .cursor-plugin/plugin.json | head -1)"
[ -n "$cursor_version" ] || fail "could not read \"version\" from .cursor-plugin/plugin.json."
if [ "$cursor_version" != "$plugin_version" ]; then
  fail ".cursor-plugin/plugin.json is version ${cursor_version}, but .claude-plugin/plugin.json is ${plugin_version}."
fi

echo "version $plugin_version is consistent across the plugin manifests, marketplace.json, the OpenAI package and the Cursor manifest"
