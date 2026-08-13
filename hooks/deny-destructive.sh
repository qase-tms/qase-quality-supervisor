#!/bin/bash
#
# PreToolUse hook: denies any Qase MCP tool call matched by hooks.json's
# "mcp__qase__.*delete.*" pattern.
#
# Fail-closed by design: no jq dependency, and any unexpected internal
# failure blocks the call (exit 2) rather than letting it through. Per the
# Claude Code PreToolUse contract, only "exit 0 + deny JSON on stdout" and
# "exit 2" are blocking outcomes — any other non-zero exit is a non-blocking
# error and the tool call proceeds. This script must never take that path.

set -u

fail_closed() {
  echo "deny-destructive.sh: ${1:-unexpected internal error} — blocking call as a precaution." >&2
  exit 2
}

input="$(cat 2>/dev/null)"
if [ "$?" -ne 0 ]; then
  fail_closed "could not read stdin"
fi

# Best-effort extraction of tool_name via sed — no jq dependency. The
# PreToolUse matcher in hooks.json already guarantees only destructive tools
# reach this script, so a failed/empty extraction only affects the message
# text below, never the decision (which is always "deny"). This is not
# safety-relevant, so a failure here falls back to a placeholder instead of
# blocking.
tool_name="$(printf '%s' "$input" 2>/dev/null | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null | head -n1 2>/dev/null)"
if [ -z "$tool_name" ]; then
  tool_name="an unknown tool"
fi

# Escaping IS safety-relevant (it is what keeps the output valid JSON), so a
# failure here blocks rather than risking malformed/unescaped output.
escaped_tool_name="$(printf '%s' "$tool_name" | sed 's/\\/\\\\/g; s/"/\\"/g')"
if [ "$?" -ne 0 ]; then
  fail_closed "could not prepare the deny message"
fi

cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Destructive tools are disabled in Quality Supervisor — skills never delete Qase data. Blocked call to ${escaped_tool_name}."
  }
}
JSON

exit 0
