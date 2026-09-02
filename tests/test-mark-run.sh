#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/mark-run.js"
PLUGIN_VERSION="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
  "$SCRIPT_DIR/../.claude-plugin/plugin.json" | head -1)"

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

# Each case gets its own TMPDIR so state never leaks between tests.
run_hook() {
  TMPDIR="$(mktemp -d)" node "$HOOK"
}

# --- A Qase call with no run open still names the integration ---------------

input='{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"mcp__qase__qase_get","tool_input":{"entity":"case","id":7}}'
output="$(printf '%s' "$input" | run_hook)"

integration="$(echo "$output" | jq -r '.hookSpecificOutput.updatedInput._qase_integration // empty')"
if [ "$integration" != "quality-supervisor/$PLUGIN_VERSION" ]; then
  fail "expected integration 'quality-supervisor/$PLUGIN_VERSION', got '$integration'"
else
  pass "stamps the integration with the manifest version"
fi

# --- The original arguments survive verbatim --------------------------------

entity="$(echo "$output" | jq -r '.hookSpecificOutput.updatedInput.entity // empty')"
id="$(echo "$output" | jq -r '.hookSpecificOutput.updatedInput.id // empty')"
if [ "$entity" != "case" ] || [ "$id" != "7" ]; then
  fail "original arguments were altered: entity='$entity' id='$id'"
else
  pass "leaves the original arguments intact"
fi

# --- No producer when no run is open ----------------------------------------

producer="$(echo "$output" | jq -r '.hookSpecificOutput.updatedInput._qase_producer // "absent"')"
if [ "$producer" != "absent" ]; then
  fail "expected no producer outside a run, got '$producer'"
else
  pass "omits the producer outside a run"
fi

# --- A non-Qase tool is not touched -----------------------------------------

other="$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' | run_hook)"
if [ -n "$other" ]; then
  fail "hook produced output for a non-Qase tool: $other"
else
  pass "ignores tools it does not own"
fi

# --- Malformed stdin is survivable ------------------------------------------

garbage="$(printf '%s' 'not json at all' | run_hook)"
status=$?
if [ "$status" -ne 0 ]; then
  fail "hook exited $status on malformed input; must always exit 0"
elif [ -n "$garbage" ]; then
  fail "hook produced output for malformed input: $garbage"
else
  pass "fails open on malformed input"
fi

# --- Empty stdin is survivable ----------------------------------------------

empty="$(printf '%s' '' | run_hook)"
if [ "$?" -ne 0 ] || [ -n "$empty" ]; then
  fail "hook did not fail open on empty input"
else
  pass "fails open on empty input"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "All mark-run checks passed."
