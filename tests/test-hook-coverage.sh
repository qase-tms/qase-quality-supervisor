#!/bin/bash
# Every destructive matcher must be guarded on every platform. A guard that
# cannot run is not a guard: Claude Code uses Git Bash on Windows and falls back
# to PowerShell when it is absent, so a .sh-only hook is silently absent there.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_JSON="$SCRIPT_DIR/../hooks/hooks.json"
HOOKS_DIR="$SCRIPT_DIR/../hooks"

failures=0
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

for guard in deny-destructive deny-destructive-api; do
  for ext in sh ps1; do
    if [ ! -f "$HOOKS_DIR/$guard.$ext" ]; then
      fail "$guard.$ext is missing; the guard is absent wherever that shell is the only one available"
    fi
  done
  if ! grep -q "$guard.ps1" "$HOOKS_JSON"; then
    fail "$guard.ps1 exists but is not registered in hooks.json"
  fi
done

# Claude Code names a plugin server's tools mcp__plugin_<plugin>_<server>__*, and
# a user's own server named qase gives mcp__qase__*; a guard must catch both.
if ! /usr/bin/python3 -c "
import json, re, sys, io
ms = [g['matcher'] for g in json.load(io.open(sys.argv[1], encoding='utf-8'))['hooks']['PreToolUse']]
for prefix in ('mcp__qase__', 'mcp__plugin_quality-supervisor_qase__'):
    for tool in ('qase_case_delete', 'qase_api'):
        if not any(re.fullmatch(m, prefix + tool) for m in ms):
            print(prefix + tool); sys.exit(1)
    if any(re.fullmatch(m, prefix + 'qql_search') for m in ms):
        print(prefix + 'qql_search is guarded too'); sys.exit(1)
" "$HOOKS_JSON"; then
  fail "hooks.json matchers miss a Qase tool name (see above)"
fi

if [ "$failures" -gt 0 ]; then exit 1; fi
echo "All destructive matchers are guarded on both shells."
