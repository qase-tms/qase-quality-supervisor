#!/bin/bash
#
# PreToolUse hook: denies every Qase MCP call hooks.json routes here (tool names
# containing "delete").
#
# The answer is one fixed line that no input can change, printed by a builtin.
# Only "exit 0 + deny JSON" and "exit 2" block a PreToolUse call; any other exit
# lets it through, so an internal failure exits 2.

set -u
trap 'echo "deny-destructive.sh: internal error, blocking the call." >&2; exit 2' ERR

while IFS= read -r _; do :; done

echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Destructive tools are disabled in Quality Supervisor: skills never delete Qase data."}}'
exit 0
