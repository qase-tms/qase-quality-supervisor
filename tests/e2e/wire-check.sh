#!/bin/bash
# End-to-end: does the marker survive a real Claude Code session?
#
# NOT part of the tests/test-*.sh glob: needs the claude binary, starts a real
# session and costs tokens. Run before a release, not on every commit.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORK="$(mktemp -d)"
export WIRE_LOG="$WORK/wire.log"
: > "$WIRE_LOG"

command -v claude >/dev/null || { echo "SKIP: claude not on PATH"; exit 0; }

cat > "$WORK/mcp.json" <<JSON
{ "mcpServers": { "qase": { "command": "node", "args": ["$SCRIPT_DIR/spike-server.mjs"], "env": { "WIRE_LOG": "$WIRE_LOG" } } } }
JSON

# The plugin's own hooks, read from hooks/hooks.json rather than restated here.
/usr/bin/python3 "$SCRIPT_DIR/settings-from-hooks.py" "$REPO_ROOT" "$WORK/settings.json"

run_claude() {
  claude -p "$1" --mcp-config "$WORK/mcp.json" --strict-mcp-config \
    --settings "$WORK/settings.json" \
    --allowedTools "mcp__qase__qase_qql" "Skill" < /dev/null > /dev/null 2>&1
}

failures=0
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

# 1. A call with no skill carries the integration but no producer.
run_claude "Call the qase_qql tool once with query \"x\". Then stop."
first="$(head -1 "$WIRE_LOG")"
echo "$first" | jq -e '.arguments._qase_integration | startswith("quality-supervisor/")' >/dev/null \
  || fail "the integration marker did not reach the wire: $first"
echo "$first" | jq -e 'has("arguments") and (.arguments | has("_qase_producer") | not)' >/dev/null \
  || fail "a call outside a skill carried a producer: $first"

# 2. THE MANDATORY CHECK: a new prompt after Stop is not attributed to the
#    skill that ran in the previous one.
: > "$WIRE_LOG"
run_claude "Use the quality-supervisor:analyzing-test-coverage skill, then stop."
: > "$WIRE_LOG"
run_claude "Call the qase_qql tool once with query \"after\". Then stop."
after="$(head -1 "$WIRE_LOG")"
# An empty log would let the check above pass without ever testing anything, so
# absence of evidence is a failure here rather than a silent success.
if [ -z "$after" ]; then
  fail "the second prompt produced no Qase call, so the run-boundary check never ran"
else
  echo "$after" | jq -e '.arguments | has("_qase_producer") | not' >/dev/null \
    || fail "a call in a NEW prompt was attributed to the previous prompt's skill: $after"
  echo "$after" | jq -e '.arguments._qase_integration | startswith("quality-supervisor/")' >/dev/null \
    || fail "the second prompt's call lost its integration marker: $after"
fi

rm -rf "$WORK"
[ "$failures" -gt 0 ] && exit 1
echo "Wire check passed."
