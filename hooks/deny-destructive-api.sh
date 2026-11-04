#!/bin/bash
#
# PreToolUse hook for qase_api, a raw API passthrough whose name never matches
# the delete pattern even though it can send a DELETE. Denies the call when the
# payload asks for one; otherwise prints nothing and the normal permission flow
# continues.
#
# Fail-closed, two ways:
#  1. Only bash builtins, so a missing binary cannot let a DELETE through. An
#     earlier version shelled out to sed unchecked, and a missing sed did.
#  2. Over-broad on purpose: ANY "method": "delete" in the payload denies. A
#     decoy can only cause a needless denial. An earlier version matched the
#     LAST "method", so a trailing "method": "GET" hid a real DELETE.
#
# The deny answer is one fixed line. Only "exit 0 + deny JSON" and "exit 2"
# block a PreToolUse call, so an internal failure exits 2.

set -u
trap 'echo "deny-destructive-api.sh: internal error, blocking the call." >&2; exit 2' ERR

input=""
while IFS= read -r line || [ -n "$line" ]; do
  input="${input}${line}"
done

shopt -s nocasematch
delete_method='"method"[^"]*"delete"'

if [[ $input =~ $delete_method ]]; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"DELETE through qase_api is disabled in Quality Supervisor: skills never delete Qase data."}}'
fi

exit 0
