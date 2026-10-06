#!/bin/bash
#
# Sets the plugin version everywhere it appears, in one command.
#
# The version lives in three places — the Claude Code plugin manifest, the Codex
# plugin manifest, and the marketplace manifest — because none of them can read
# the others. It used to live in four: the
# X-Qase-Integration marker in .mcp.json and the self-run example in README.md
# are gone, since hooks/mark-run.js reads the manifest at runtime and puts the
# version on the wire itself. This script is still the single entry point, and
# scripts/check-version-sync.sh is the net under it.
#
# Deliberately rewrites by pattern rather than by the current value, so it also
# repairs a repository that is already out of sync.
#
# Usage: set-version.sh <version> [repo-root]
#   e.g. set-version.sh 0.2.0

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <version> [repo-root]" >&2
  exit 1
fi

NEW_VERSION="$1"
# Resolved before the cd: the check script lives beside this one, which is not
# necessarily inside the repository being rewritten (the tests pass a fixture).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${2:-$(cd "$SCRIPT_DIR/.." && pwd)}"
cd "$REPO_ROOT"


# Semver only. The MCP server validates the marker's version against
# ^[\w.\-+]{1,32}$ and silently drops anything else — keeping the name but losing
# the version — so a malformed value here would degrade metrics rather than fail.
if ! printf '%s' "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'; then
  echo "FAIL: '$NEW_VERSION' is not a semver version (expected e.g. 0.2.0 or 0.2.0-rc.1)." >&2
  exit 1
fi

# Replace the first "version": "..." in a JSON manifest, and confirm it took.
set_manifest_version() {
  local file="$1" before after
  before="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$file" | head -1)"
  if [ -z "$before" ]; then
    echo "FAIL: no \"version\" field found in $file." >&2
    exit 1
  fi
  # -i.bak (no space) is the one form both BSD and GNU sed accept.
  sed -i.bak -E "1,/\"version\"[[:space:]]*:/ s/(\"version\"[[:space:]]*:[[:space:]]*\")[^\"]+(\")/\1${NEW_VERSION}\2/" "$file"
  rm -f "$file.bak"
  after="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$file" | head -1)"
  if [ "$after" != "$NEW_VERSION" ]; then
    echo "FAIL: $file still reads $after after the rewrite." >&2
    exit 1
  fi
  printf '  %-34s %s -> %s\n' "$file" "$before" "$after"
}

echo "==> Setting version to $NEW_VERSION"
set_manifest_version .claude-plugin/plugin.json
set_manifest_version .claude-plugin/marketplace.json
set_manifest_version .codex-plugin/plugin.json

echo "==> Verifying"
bash "$SCRIPT_DIR/check-version-sync.sh" "$REPO_ROOT"

echo
echo "Next: add a CHANGELOG.md entry for $NEW_VERSION, then commit."
