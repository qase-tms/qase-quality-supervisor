#!/bin/bash
#
# Asserts that every place carrying this plugin's version agrees with
# .claude-plugin/plugin.json, which is the single source of truth.
#
# Four files repeat the version, and one of them — the X-Qase-Integration marker
# in .mcp.json — is not merely cosmetic: it rides along on every Qase MCP call
# and is recorded in Qase analytics (see SECURITY.md). Nothing builds it from the
# manifest at runtime, because .mcp.json has no way to interpolate the plugin
# version. A stale marker therefore fails silently: an outdated version string
# passes the server's validation exactly as well as a correct one, so the calls
# keep being counted, just filed under a version nobody is running.
#
# Called by scripts/verify-plugin.sh (so CI enforces it on every push) and by
# .githooks/pre-commit (so a release bump is caught before the push). Both share
# this file rather than reimplementing the comparison.
#
# Usage: check-version-sync.sh [repo-root]   (defaults to this repo)

set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$REPO_ROOT"

INTEGRATION_NAME="quality-supervisor"

fail() {
  echo "FAIL: $1" >&2
  echo "      Run scripts/set-version.sh <version> to update every place at once." >&2
  exit 1
}

plugin_version="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' .claude-plugin/plugin.json | head -1)"
[ -n "$plugin_version" ] || fail "could not read \"version\" from .claude-plugin/plugin.json."

expected_marker="${INTEGRATION_NAME}/${plugin_version}"

# The marketplace manifest carries its own copy, and a marketplace whose version
# trails the plugin's misreports what installers are offered.
marketplace_version="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' .claude-plugin/marketplace.json | head -1)"
[ -n "$marketplace_version" ] || fail "could not read \"version\" from .claude-plugin/marketplace.json."
if [ "$marketplace_version" != "$plugin_version" ]; then
  fail ".claude-plugin/marketplace.json is version ${marketplace_version}, but .claude-plugin/plugin.json is ${plugin_version}."
fi

# Two accepted marker forms: the X-Qase-Integration header, and ?integration= on
# the URL for clients whose OAuth flow strips custom headers. The MCP server
# takes either, so accept either here too.
marker="$(sed -nE 's/.*"X-Qase-Integration"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' .mcp.json | head -1)"
if [ -z "$marker" ]; then
  marker="$(sed -nE 's/.*[?&]integration=([^"&]+).*/\1/p' .mcp.json | head -1)"
fi
[ -n "$marker" ] || fail ".mcp.json declares no integration marker — expected an \"X-Qase-Integration\" header or ?integration= on the server URL. Without it, plugin usage cannot be attributed to a team."
if [ "$marker" != "$expected_marker" ]; then
  fail ".mcp.json declares marker '${marker}', but .claude-plugin/plugin.json is version ${plugin_version}; expected '${expected_marker}'."
fi

# The self-run instructions carry the same marker as a QASE_MCP_INTEGRATION env
# var; a stale copy there misattributes every self-run user.
while read -r readme_marker; do
  if [ "$readme_marker" != "$expected_marker" ]; then
    fail "README.md documents marker '${readme_marker}', but expected '${expected_marker}'."
  fi
done < <(grep -oE "${INTEGRATION_NAME}/[0-9][^\"' ]*" README.md || true)

echo "version $plugin_version is consistent across plugin.json, marketplace.json, .mcp.json ($marker) and README.md"
