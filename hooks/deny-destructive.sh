#!/bin/bash
set -euo pipefail

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name')"

jq -n --arg tool "$tool_name" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Destructive tools are disabled in Quality Supervisor — skills never delete Qase data. Blocked call to " + $tool + ".")
  }
}'
exit 0
