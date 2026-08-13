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

# --- deny-destructive-api.sh: a decoy method must not mask a real DELETE ----
#
# Regression test. The guard cannot resolve tool_input.method precisely without
# a JSON parser, so it denies on ANY "method":"delete" in the payload. An
# earlier version matched the LAST occurrence instead, so appending
# '"method":"GET"' let a genuine DELETE through with no broken environment at
# all — the worst of the fail-open cases, because nothing looked wrong.

decoy_output="$(echo '{"tool_name":"mcp__qase__qase_api","tool_input":{"method":"DELETE","endpoint":"/case/PRJ/1","meta":{"method":"GET"}}}' | "$API_HOOK")"
decoy_decision="$(echo "$decoy_output" | jq -r '.hookSpecificOutput.permissionDecision')"

if [ "$decoy_decision" != "deny" ]; then
  fail "deny-destructive-api.sh: a trailing decoy \"method\":\"GET\" masked a real DELETE (decision='$decoy_decision')"
fi
echo "PASS: deny-destructive-api.sh still denies when a decoy method follows a real DELETE"

# --- deny-destructive-api.sh: no external binaries required ------------------
#
# Regression test. The DELETE check uses only bash builtins, so an empty PATH
# must not change the verdict. An earlier version shelled out to sed without
# checking its exit status, and a missing sed silently allowed DELETEs.
# NOTE: invoke bash by absolute path — `PATH=... bash` would resolve `bash`
# itself against the empty PATH and exit 127 before the hook ever ran, which
# looks like a hook failure but isn't.

empty_bin="$(mktemp -d)"
trap 'rm -rf "$minimal_bin" "$broken_bin" "$empty_bin"' EXIT

set +e
nopath_output="$(echo '{"tool_name":"mcp__qase__qase_api","tool_input":{"method":"DELETE"}}' | PATH="$empty_bin" /bin/bash "$API_HOOK" 2>/dev/null)"
nopath_exit=$?
set -e

if [ "$nopath_exit" -eq 2 ]; then
  echo "PASS: deny-destructive-api.sh fails closed (exit 2) with an empty PATH"
elif [ "$nopath_exit" -eq 0 ] && printf '%s' "$nopath_output" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
  echo "PASS: deny-destructive-api.sh still denies DELETE with an empty PATH"
else
  fail "deny-destructive-api.sh did not block DELETE with an empty PATH: exit=$nopath_exit output=$nopath_output"
fi

# --- deny-destructive-api.sh: GET stays allowed with an empty PATH -----------
#
# The over-broad denial must not become "deny everything" when the environment
# is stripped — a guard that blocks every qase_api call would break the skills.

set +e
nopath_get_output="$(echo '{"tool_name":"mcp__qase__qase_api","tool_input":{"method":"GET"}}' | PATH="$empty_bin" /bin/bash "$API_HOOK" 2>/dev/null)"
nopath_get_exit=$?
set -e

if [ "$nopath_get_exit" -ne 0 ] || [ -n "$nopath_get_output" ]; then
  fail "deny-destructive-api.sh should allow GET with an empty PATH: exit=$nopath_get_exit output=$nopath_get_output"
fi
echo "PASS: deny-destructive-api.sh allows method=GET with an empty PATH"

echo "All deny-destructive tests passed."
