#!/bin/bash
#
# The plugin ships two hook files: hooks.json for Claude Code and
# hooks.codex.json for Codex. They differ on purpose — Codex takes a single
# command string rather than command + args, rejects the usage-attribution hook's
# updatedInput, and surfaces the missing PowerShell interpreter as a visible error
# on unix. What they must never differ on is which calls are guarded: a matcher
# added to one file and forgotten in the other leaves one host unprotected, and
# nothing else would notice.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."

failures=0
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }
pass() { echo "PASS: $1"; }

guards() {   # destructive matchers declared in $1
  /usr/bin/python3 -c "
import json, sys, io
d = json.load(io.open(sys.argv[1], encoding='utf-8'))
ms = [g.get('matcher','') for g in d['hooks'].get('PreToolUse', [])]
print('\n'.join(sorted(m for m in ms if 'delete' in m or m == 'mcp__qase__qase_api')))
" "$1"
}

claude_guards="$(guards "$ROOT/hooks/hooks.json")"
codex_guards="$(guards "$ROOT/hooks/hooks.codex.json")"

if [ -z "$claude_guards" ]; then
  fail "hooks.json declares no destructive matchers at all"
elif [ "$claude_guards" != "$codex_guards" ]; then
  fail "the two hook files guard different calls:
  hooks.json:       $(echo "$claude_guards" | tr '\n' ' ')
  hooks.codex.json: $(echo "$codex_guards" | tr '\n' ' ')"
else
  pass "both hook files guard the same calls"
fi

# Codex ignores command + args, so an entry in that form would silently never run.
if /usr/bin/python3 -c "
import json, sys, io
d = json.load(io.open('$ROOT/hooks/hooks.codex.json', encoding='utf-8'))
bad = [h for gs in d['hooks'].values() for g in gs for h in g['hooks'] if 'args' in h]
sys.exit(1 if bad else 0)
"; then
  pass "hooks.codex.json uses only the single-command form Codex accepts"
else
  fail "hooks.codex.json contains a command + args entry, which Codex silently ignores"
fi

# The manifest must point at the Codex file, not the Claude Code one.
declared="$(/usr/bin/python3 -c "
import json, io
print(json.load(io.open('$ROOT/.codex-plugin/plugin.json', encoding='utf-8')).get('hooks',''))
")"
if [ "$declared" != "./hooks/hooks.codex.json" ]; then
  fail ".codex-plugin/plugin.json declares hooks '$declared', expected ./hooks/hooks.codex.json"
else
  pass "the Codex manifest points at the Codex hook file"
fi


# The Codex attribution hook approves the calls it marks, so the blast radius of
# that approval is the whole risk of the design. Checked against the server's full
# tool list, not a sample.
if /usr/bin/python3 "$SCRIPT_DIR/check-marker-scope.py" "$ROOT"; then
  :
else
  fail "the attribution hook's approval reaches the wrong tools"
fi

if [ "$failures" -gt 0 ]; then exit 1; fi
echo "Hook parity checks passed."
