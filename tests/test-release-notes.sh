#!/bin/bash
#
# Tests scripts/release-notes.sh against fixture changelogs.
#
# The release workflow publishes whatever this prints, so the failure that matters is
# a silent one: notes for the wrong version, or empty notes that still exit 0 and
# produce a blank release. Both are covered below.

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/release-notes.sh"

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

fixture="$(mktemp)"
cat > "$fixture" <<'EOF'
# Changelog

All notable changes are documented in this file.

## [0.2.0] - 2026-08-20

### Added
- Second thing.
- Another second thing.

### Changed
- A change.

## [0.1.1] - 2026-08-20

### Added
- Middle thing.

## [0.1.0] - 2026-08-18

First release.

### Added
- First thing.
EOF

# --- a middle section stops at the next heading ---------------------------

out="$(bash "$SCRIPT" 0.2.0 "$fixture")"
if [ "$out" = "### Added
- Second thing.
- Another second thing.

### Changed
- A change." ]; then
  pass "extracts a section and stops at the next version heading"
else
  fail "wrong body for 0.2.0; got:
$out"
fi

# --- the last section runs to end of file --------------------------------

out="$(bash "$SCRIPT" 0.1.0 "$fixture")"
if [ "$out" = "First release.

### Added
- First thing." ]; then
  pass "extracts the last section to end of file"
else
  fail "wrong body for the final section; got:
$out"
fi

# --- no leading or trailing blank lines ----------------------------------

out="$(bash "$SCRIPT" 0.1.1 "$fixture")"
first="$(printf '%s\n' "$out" | head -1)"
last="$(printf '%s\n' "$out" | tail -1)"
if [ -n "$first" ] && [ -n "$last" ]; then
  pass "trims surrounding blank lines"
else
  fail "left a blank line at an edge"
fi

# --- a version that was never written up must fail, not publish empty ----

if bash "$SCRIPT" 9.9.9 "$fixture" >/dev/null 2>&1; then
  fail "exited 0 for a version with no section"
else
  pass "fails for a version with no section"
fi

# --- a heading with no content is also a failure -------------------------

empty="$(mktemp)"
printf '# Changelog\n\n## [0.4.0] - 2026-08-21\n\n## [0.3.0] - 2026-08-20\n\n- Real content.\n' > "$empty"
if bash "$SCRIPT" 0.4.0 "$empty" >/dev/null 2>&1; then
  fail "exited 0 for a heading with no content"
else
  pass "fails for a heading with no content"
fi
rm -f "$empty"

# --- the version is matched literally, not as a regex --------------------
#
# "0.1.1" as a regex would also match "0111"; a dotted version must not.

dotty="$(mktemp)"
printf '# Changelog\n\n## [0111] - 2026-08-20\n\n- Wrong section.\n' > "$dotty"
if bash "$SCRIPT" 0.1.1 "$dotty" >/dev/null 2>&1; then
  fail "matched a dotted version against a digits-only heading"
else
  pass "matches the version literally, not as a regex"
fi
rm -f "$dotty"

# --- a missing changelog fails loudly ------------------------------------

if bash "$SCRIPT" 0.1.0 /nonexistent/CHANGELOG.md >/dev/null 2>&1; then
  fail "exited 0 with no changelog present"
else
  pass "fails when the changelog is missing"
fi

# --- the real changelog: every shipped version must have notes -----------
#
# This is the check that catches a release cut without a changelog entry.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
current="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$REPO_ROOT/.claude-plugin/plugin.json" | head -1)"
if bash "$SCRIPT" "$current" "$REPO_ROOT/CHANGELOG.md" >/dev/null 2>&1; then
  pass "the current version ($current) has release notes in the real CHANGELOG"
else
  fail "the current version ($current) has no section in CHANGELOG.md"
fi

rm -f "$fixture"

if [ "$failures" -ne 0 ]; then
  echo "$failures release-notes test(s) failed." >&2
  exit 1
fi
echo "All release-notes tests passed."
