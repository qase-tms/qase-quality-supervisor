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

if [ "$failures" -gt 0 ]; then exit 1; fi
echo "All destructive matchers are guarded on both shells."
