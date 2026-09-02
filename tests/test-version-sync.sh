#!/bin/bash
#
# Tests scripts/check-version-sync.sh and scripts/set-version.sh against throwaway
# fixture repositories, so the failure modes are exercised rather than assumed.
#
# Both scripts accept a repo root as their last argument for exactly this reason:
# asserting on the real repository could only ever confirm the happy path, and the
# whole point of the check is what it does when the version strings drift.
#
# The version used to live in four places; two of them — the X-Qase-Integration
# marker in .mcp.json and the self-run example in README.md — are gone, because
# hooks/mark-run.js now reads .claude-plugin/plugin.json at runtime and puts the
# version on the wire itself. What remains are the two manifests, which genuinely
# cannot read each other.

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
CHECK="$SCRIPTS_DIR/check-version-sync.sh"
SET_VERSION="$SCRIPTS_DIR/set-version.sh"

failures=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

# A fixture repo carrying $1 as the plugin version, with every copy consistent.
make_fixture() {
  local version="$1" root
  root="$(mktemp -d)"
  mkdir -p "$root/.claude-plugin"
  cat > "$root/.claude-plugin/plugin.json" <<EOJ
{
  "name": "quality-supervisor",
  "version": "$version",
  "description": "fixture"
}
EOJ
  cat > "$root/.claude-plugin/marketplace.json" <<EOJ
{
  "name": "quality-supervisor",
  "metadata": {
    "version": "$version"
  }
}
EOJ
  echo "$root"
}

# --- check: the consistent case passes -------------------------------------

root="$(make_fixture 0.1.0)"
if bash "$CHECK" "$root" >/dev/null 2>&1; then
  pass "check-version-sync accepts a consistent repository"
else
  fail "check-version-sync rejected a consistent repository"
fi
rm -rf "$root"

# --- check: a drifting marketplace manifest is caught ----------------------
#
# A marketplace whose version trails the plugin's misreports what installers are
# offered, which is the one drift that survives the marker's removal.

root="$(make_fixture 0.1.0)"
sed -i.bak 's|"version": "0.1.0"|"version": "0.3.0"|' "$root/.claude-plugin/marketplace.json"
if bash "$CHECK" "$root" >/dev/null 2>&1; then
  fail "check-version-sync missed a marketplace manifest trailing the plugin"
else
  pass "check-version-sync catches a marketplace manifest trailing the plugin"
fi
rm -rf "$root"

# --- check: an unreadable plugin version is a failure, not a pass ----------

root="$(make_fixture 0.1.0)"
echo '{ "name": "quality-supervisor" }' > "$root/.claude-plugin/plugin.json"
if bash "$CHECK" "$root" >/dev/null 2>&1; then
  fail "check-version-sync passed a plugin.json with no version"
else
  pass "check-version-sync catches a plugin.json with no version"
fi
rm -rf "$root"

# --- set-version: bumps every copy, and repairs existing drift ------------

root="$(make_fixture 0.1.0)"
if bash "$SET_VERSION" 0.2.0 "$root" >/dev/null 2>&1 && bash "$CHECK" "$root" >/dev/null 2>&1; then
  if grep -q '"version": "0.2.0"' "$root/.claude-plugin/plugin.json" &&
    grep -q '"version": "0.2.0"' "$root/.claude-plugin/marketplace.json"; then
    pass "set-version bumps both manifests"
  else
    fail "set-version left a copy behind"
  fi
else
  fail "set-version did not produce a consistent repository"
fi
rm -rf "$root"

root="$(make_fixture 0.1.0)"
sed -i.bak 's|"version": "0.1.0"|"version": "0.0.1"|' "$root/.claude-plugin/marketplace.json"
if bash "$SET_VERSION" 0.4.0 "$root" >/dev/null 2>&1 && bash "$CHECK" "$root" >/dev/null 2>&1; then
  pass "set-version repairs a repository that was already out of sync"
else
  fail "set-version could not repair pre-existing drift"
fi
rm -rf "$root"

# --- set-version: rejects a version the MCP server would drop -------------
#
# The server validates the marker version against ^[\w.\-+]{1,32}$ and silently
# keeps the name while dropping a bad version, so garbage must be refused here.
# The version now reaches the server from the hook rather than from .mcp.json,
# but it is the same field on the far end and the same silent degradation.

root="$(make_fixture 0.1.0)"
if bash "$SET_VERSION" "not a version" "$root" >/dev/null 2>&1; then
  fail "set-version accepted a non-semver version"
else
  pass "set-version rejects a non-semver version"
fi
rm -rf "$root"

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "All version-sync checks passed."
