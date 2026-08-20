#!/bin/bash
#
# Tests scripts/check-version-sync.sh and scripts/set-version.sh against throwaway
# fixture repositories, so the failure modes are exercised rather than assumed.
#
# Both scripts accept a repo root as their last argument for exactly this reason:
# asserting on the real repository could only ever confirm the happy path, and the
# whole point of the check is what it does when the version strings drift.

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
  cat > "$root/.claude-plugin/plugin.json" <<EOF
{
  "name": "quality-supervisor",
  "version": "$version",
  "description": "fixture"
}
EOF
  cat > "$root/.claude-plugin/marketplace.json" <<EOF
{
  "name": "quality-supervisor",
  "metadata": {
    "version": "$version"
  }
}
EOF
  cat > "$root/.mcp.json" <<EOF
{
  "mcpServers": {
    "qase": {
      "type": "http",
      "url": "https://mcp.qase.io/mcp",
      "headers": {
        "X-Qase-Integration": "quality-supervisor/$version"
      }
    }
  }
}
EOF
  cat > "$root/README.md" <<EOF
Self-run: "QASE_MCP_INTEGRATION": "quality-supervisor/$version"
Repo link that must not be mistaken for a marker: qase-tms/qase-quality-supervisor
EOF
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

# --- check: each drifting copy is caught -----------------------------------

root="$(make_fixture 0.1.0)"
sed -i.bak 's|quality-supervisor/0.1.0|quality-supervisor/0.9.9|' "$root/.mcp.json"
if bash "$CHECK" "$root" >/dev/null 2>&1; then
  fail "check-version-sync missed a stale marker in .mcp.json"
else
  pass "check-version-sync catches a stale marker in .mcp.json"
fi
rm -rf "$root"

root="$(make_fixture 0.1.0)"
sed -i.bak 's|quality-supervisor/0.1.0|quality-supervisor/0.2.0|' "$root/README.md"
if bash "$CHECK" "$root" >/dev/null 2>&1; then
  fail "check-version-sync missed a stale marker in README.md"
else
  pass "check-version-sync catches a stale marker in README.md"
fi
rm -rf "$root"

root="$(make_fixture 0.1.0)"
sed -i.bak 's|"version": "0.1.0"|"version": "0.3.0"|' "$root/.claude-plugin/marketplace.json"
if bash "$CHECK" "$root" >/dev/null 2>&1; then
  fail "check-version-sync missed a marketplace manifest trailing the plugin"
else
  pass "check-version-sync catches a marketplace manifest trailing the plugin"
fi
rm -rf "$root"

# --- check: a missing marker is a failure, not a pass ----------------------
#
# The regression that matters most: drop the marker and attribution silently
# stops, so absence must fail as loudly as a mismatch.

root="$(make_fixture 0.1.0)"
cat > "$root/.mcp.json" <<'EOF'
{
  "mcpServers": {
    "qase": {
      "type": "http",
      "url": "https://mcp.qase.io/mcp"
    }
  }
}
EOF
if bash "$CHECK" "$root" >/dev/null 2>&1; then
  fail "check-version-sync passed a .mcp.json with no integration marker"
else
  pass "check-version-sync catches a missing integration marker"
fi
rm -rf "$root"

# --- check: the ?integration= fallback form is accepted --------------------

root="$(make_fixture 0.1.0)"
cat > "$root/.mcp.json" <<'EOF'
{
  "mcpServers": {
    "qase": {
      "type": "http",
      "url": "https://mcp.qase.io/mcp?integration=quality-supervisor/0.1.0"
    }
  }
}
EOF
if bash "$CHECK" "$root" >/dev/null 2>&1; then
  pass "check-version-sync accepts the ?integration= marker form"
else
  fail "check-version-sync rejected the ?integration= marker form"
fi
rm -rf "$root"

# --- set-version: bumps every copy, and repairs existing drift ------------

root="$(make_fixture 0.1.0)"
if bash "$SET_VERSION" 0.2.0 "$root" >/dev/null 2>&1 && bash "$CHECK" "$root" >/dev/null 2>&1; then
  if grep -q '"version": "0.2.0"' "$root/.claude-plugin/plugin.json" &&
    grep -q '"version": "0.2.0"' "$root/.claude-plugin/marketplace.json" &&
    grep -q 'quality-supervisor/0.2.0' "$root/.mcp.json" &&
    grep -q 'quality-supervisor/0.2.0' "$root/README.md"; then
    pass "set-version bumps all four copies"
  else
    fail "set-version left a copy behind"
  fi
else
  fail "set-version did not produce a consistent repository"
fi
rm -rf "$root"

root="$(make_fixture 0.1.0)"
sed -i.bak 's|quality-supervisor/0.1.0|quality-supervisor/0.0.1|' "$root/.mcp.json"
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

root="$(make_fixture 0.1.0)"
if bash "$SET_VERSION" "not a version" "$root" >/dev/null 2>&1; then
  fail "set-version accepted a non-semver version"
else
  pass "set-version rejects a non-semver version"
fi
rm -rf "$root"

# --- set-version: leaves nothing behind -----------------------------------

root="$(make_fixture 0.1.0)"
bash "$SET_VERSION" 0.5.0 "$root" >/dev/null 2>&1
leftovers="$(find "$root" -name '*.bak' | wc -l | tr -d ' ')"
if [ "$leftovers" = "0" ]; then
  pass "set-version leaves no .bak files behind"
else
  fail "set-version left $leftovers .bak file(s) behind"
fi
rm -rf "$root"

if [ "$failures" -ne 0 ]; then
  echo "$failures version-sync test(s) failed." >&2
  exit 1
fi
echo "All version-sync tests passed."
