#!/bin/bash
#
# PreToolUse hook for mcp__qase__qase_api. That tool is a raw API passthrough
# accepting method: GET|POST|PUT|PATCH|DELETE, so it doesn't match the
# "mcp__qase__.*delete.*" name pattern used by deny-destructive.sh even though
# it can issue a DELETE. This hook closes that gap: it denies the call only
# when tool_input.method is DELETE, and otherwise allows the normal
# permission flow to continue untouched (exit 0, no stdout).
#
# Fail-closed by design: no jq dependency, and any unexpected internal
# failure blocks the call (exit 2) rather than letting it through.

set -u

fail_closed() {
  echo "deny-destructive-api.sh: ${1:-unexpected internal error} — blocking call as a precaution." >&2
  exit 2
}

input="$(cat 2>/dev/null)"
if [ "$?" -ne 0 ]; then
  fail_closed "could not read stdin"
fi

# Best-effort extraction of tool_input.method — no jq dependency. Failing to
# find a method is treated as "not DELETE" (allow): this guard exists only to
# catch DELETE, not to gate every other qase_api call.
method="$(printf '%s' "$input" 2>/dev/null | sed -n 's/.*"method"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null | head -n1 2>/dev/null)"

# Case-insensitive comparison IS safety-relevant: if the method can't be
# reliably normalized, a disguised DELETE (e.g. "delete") could slip through
# an exact-case check, so a failure here blocks rather than defaulting to
# allow.
method_upper="$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')"
if [ "$?" -ne 0 ]; then
  fail_closed "could not normalize the method for comparison"
fi

if [ "$method_upper" = "DELETE" ]; then
  cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "DELETE via the qase_api escape hatch is disabled in Quality Supervisor — skills never delete Qase data, including through the raw API passthrough."
  }
}
JSON
fi

exit 0
