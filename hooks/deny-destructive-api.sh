#!/bin/bash
#
# PreToolUse hook for mcp__qase__qase_api. That tool is a raw API passthrough
# accepting method: GET|POST|PUT|PATCH|DELETE, so it doesn't match the
# "mcp__qase__.*delete.*" name pattern used by deny-destructive.sh even though
# it can issue a DELETE. This hook closes that gap: it denies the call when the
# payload requests a DELETE, and otherwise lets the normal permission flow
# continue untouched (exit 0, no stdout).
#
# Fail-closed by design, two ways:
#
#  1. The DELETE check uses only bash builtins — no cat/sed/tr/jq — so there is
#     no "required binary missing" path that could silently allow a DELETE.
#     (An earlier version shelled out to sed without checking its status, and a
#     missing sed let DELETEs through.)
#  2. Detection is deliberately over-broad: ANY "method": "delete" anywhere in
#     the payload denies, rather than trying to resolve tool_input.method
#     precisely without a JSON parser. A decoy or nested method field can only
#     cause an unnecessary denial, never an unnoticed deletion. (An earlier
#     version matched the LAST "method" in the payload, so a trailing
#     '"method":"GET"' let a genuine DELETE through.)
#
# Per the Claude Code PreToolUse contract, only "exit 0 + deny JSON on stdout"
# and "exit 2" are blocking outcomes — any other non-zero exit is a
# non-blocking error and the tool call proceeds. This script must never take
# that path, so anything unexpected exits 2.

set -u
trap 'echo "deny-destructive-api.sh: unexpected internal error — blocking call as a precaution." >&2; exit 2' ERR

# Read stdin using the `read` builtin so a broken PATH cannot affect this.
input=""
while IFS= read -r line || [ -n "$line" ]; do
  input="${input}${line}"
done

shopt -s nocasematch

if [[ "$input" =~ \"method\"[[:space:]]*:[[:space:]]*\"delete\" ]]; then
  # Heredoc-free so this path needs no external binary either.
  printf '%s\n' '{'
  printf '%s\n' '  "hookSpecificOutput": {'
  printf '%s\n' '    "hookEventName": "PreToolUse",'
  printf '%s\n' '    "permissionDecision": "deny",'
  printf '%s\n' '    "permissionDecisionReason": "DELETE via the qase_api escape hatch is disabled in Quality Supervisor — skills never delete Qase data, including through the raw API passthrough."'
  printf '%s\n' '  }'
  printf '%s\n' '}'
fi

exit 0
