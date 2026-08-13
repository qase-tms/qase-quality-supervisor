#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/deny-destructive.sh"
API_HOOK="$SCRIPT_DIR/../hooks/deny-destructive-api.sh"

fail() {
  echo "FAIL: $1"
  exit 1
}

minimal_bin="$(mktemp -d)"
broken_bin="$(mktemp -d)"
cleanup() {
  rm -rf "$minimal_bin" "$broken_bin"
}
trap cleanup EXIT

# minimal_bin: only what the hooks themselves use (cat, sed, head, tr), with
# jq genuinely unresolvable — proves the hooks have no jq dependency.
for cmd in cat sed head tr; do
  ln -s "$(command -v "$cmd")" "$minimal_bin/$cmd"
done
if PATH="$minimal_bin" command -v jq >/dev/null 2>&1; then
  fail "test setup broken: jq is still resolvable inside the minimal PATH"
fi

# broken_bin: missing sed/head/tr entirely, to simulate a genuine internal
# failure (not just malformed input) and prove the hooks fail closed.
ln -s "$(command -v cat)" "$broken_bin/cat"

# --- deny-destructive.sh: normal deny case ----------------------------------

output="$(echo '{"tool_name":"mcp__qase__qase_case_delete","tool_input":{"id":123}}' | "$HOOK")"

decision="$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision')"
reason="$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')"

if [ "$decision" != "deny" ]; then
  fail "permissionDecision was '$decision', expected 'deny'"
fi
if [[ "$reason" != *"mcp__qase__qase_case_delete"* ]]; then
  fail "reason did not mention the blocked tool: $reason"
fi

echo "PASS: deny-destructive.sh blocks mcp__qase__qase_case_delete"

# --- deny-destructive.sh: fail-closed, jq absent + malformed stdin ----------
#
# The only acceptable outcomes are: exit 2 (blocking per the PreToolUse
# contract), or exit 0 with a deny decision on stdout. Any other exit code
# would be a non-blocking error under that contract, i.e. a fail-open bug.

set +e
fc_output="$(printf '%s' 'not valid json {{{' | PATH="$minimal_bin" "$HOOK" 2>/dev/null)"
fc_exit=$?
set -e

if [ "$fc_exit" -eq 2 ]; then
  echo "PASS: deny-destructive.sh fails closed (exit 2) with jq absent + malformed stdin"
elif [ "$fc_exit" -eq 0 ] && printf '%s' "$fc_output" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
  echo "PASS: deny-destructive.sh fails closed (deny JSON) with jq absent + malformed stdin"
else
  fail "deny-destructive.sh did not fail closed: exit=$fc_exit output=$fc_output"
fi

# --- deny-destructive.sh: fail-closed, genuine internal failure -------------
#
# sed/head are entirely missing (not just jq): the hook cannot safely build
# its JSON output and must block (exit 2), not emit malformed output.

set +e
broken_output="$(echo '{"tool_name":"x"}' | PATH="$broken_bin" "$HOOK" 2>/dev/null)"
broken_exit=$?
set -e

if [ "$broken_exit" -ne 2 ]; then
  fail "deny-destructive.sh did not fail closed with sed/head missing: exit=$broken_exit output=$broken_output"
fi
echo "PASS: deny-destructive.sh fails closed (exit 2) when sed/head are missing"

# --- deny-destructive-api.sh: DELETE method is denied -----------------------

api_output="$(echo '{"tool_name":"mcp__qase__qase_api","tool_input":{"method":"DELETE","endpoint":"/case/PRJ/1"}}' | "$API_HOOK")"
api_decision="$(echo "$api_output" | jq -r '.hookSpecificOutput.permissionDecision')"

if [ "$api_decision" != "deny" ]; then
  fail "deny-destructive-api.sh: permissionDecision was '$api_decision' for DELETE, expected 'deny'"
fi
echo "PASS: deny-destructive-api.sh blocks method=DELETE"

# --- deny-destructive-api.sh: lowercase "delete" is also denied -------------

api_lc_output="$(echo '{"tool_name":"mcp__qase__qase_api","tool_input":{"method":"delete"}}' | "$API_HOOK")"
api_lc_decision="$(echo "$api_lc_output" | jq -r '.hookSpecificOutput.permissionDecision')"

if [ "$api_lc_decision" != "deny" ]; then
  fail "deny-destructive-api.sh: permissionDecision was '$api_lc_decision' for lowercase 'delete', expected 'deny'"
fi
echo "PASS: deny-destructive-api.sh blocks method=delete (case-insensitive)"

# --- deny-destructive-api.sh: GET method is allowed (no stdout) -------------

set +e
get_output="$(echo '{"tool_name":"mcp__qase__qase_api","tool_input":{"method":"GET","endpoint":"/case/PRJ/1"}}' | "$API_HOOK")"
get_exit=$?
set -e

if [ "$get_exit" -ne 0 ]; then
  fail "deny-destructive-api.sh: expected exit 0 for method=GET, got $get_exit"
fi
if [ -n "$get_output" ]; then
  fail "deny-destructive-api.sh: expected no stdout for method=GET, got: $get_output"
fi
echo "PASS: deny-destructive-api.sh allows method=GET with no stdout"

# --- deny-destructive-api.sh: fail-closed, genuine internal failure ---------
#
# tr is entirely missing: the hook cannot safely case-normalize the method
# (so a disguised "delete" could slip an exact-case check) and must block.

set +e
api_broken_bin="$broken_bin"
ln -sf "$(command -v sed)" "$api_broken_bin/sed" 2>/dev/null
ln -sf "$(command -v head)" "$api_broken_bin/head" 2>/dev/null
api_broken_output="$(echo '{"tool_name":"mcp__qase__qase_api","tool_input":{"method":"delete"}}' | PATH="$api_broken_bin" "$API_HOOK" 2>/dev/null)"
api_broken_exit=$?
set -e

if [ "$api_broken_exit" -ne 2 ]; then
  fail "deny-destructive-api.sh did not fail closed with tr missing: exit=$api_broken_exit output=$api_broken_output"
fi
echo "PASS: deny-destructive-api.sh fails closed (exit 2) when tr is missing"

echo "All deny-destructive tests passed."
