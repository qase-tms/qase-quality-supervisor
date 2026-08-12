#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/deny-destructive.sh"

output="$(echo '{"tool_name":"mcp__qase__qase_case_delete","tool_input":{"id":123}}' | "$HOOK")"

decision="$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision')"
reason="$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')"

if [ "$decision" != "deny" ]; then
  echo "FAIL: permissionDecision was '$decision', expected 'deny'"
  exit 1
fi
if [[ "$reason" != *"mcp__qase__qase_case_delete"* ]]; then
  echo "FAIL: reason did not mention the blocked tool: $reason"
  exit 1
fi

echo "PASS: deny-destructive.sh blocks mcp__qase__qase_case_delete"
