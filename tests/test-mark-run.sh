#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/mark-run.js"
PLUGIN_VERSION="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
  "$SCRIPT_DIR/../.claude-plugin/plugin.json" | head -1)"

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

# Each case gets its own TMPDIR so state never leaks between tests.
run_hook() {
  TMPDIR="$(mktemp -d)" node "$HOOK"
}

# --- A Qase call with no run open still names the integration ---------------

input='{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"mcp__qase__qase_get","tool_input":{"entity":"case","id":7}}'
output="$(printf '%s' "$input" | run_hook)"

integration="$(echo "$output" | jq -r '.hookSpecificOutput.updatedInput._qase_integration // empty')"
if [ "$integration" != "quality-supervisor/$PLUGIN_VERSION" ]; then
  fail "expected integration 'quality-supervisor/$PLUGIN_VERSION', got '$integration'"
else
  pass "stamps the integration with the manifest version"
fi

# --- The original arguments survive verbatim --------------------------------

entity="$(echo "$output" | jq -r '.hookSpecificOutput.updatedInput.entity // empty')"
id="$(echo "$output" | jq -r '.hookSpecificOutput.updatedInput.id // empty')"
if [ "$entity" != "case" ] || [ "$id" != "7" ]; then
  fail "original arguments were altered: entity='$entity' id='$id'"
else
  pass "leaves the original arguments intact"
fi

# --- No producer when no run is open ----------------------------------------

producer="$(echo "$output" | jq -r '.hookSpecificOutput.updatedInput._qase_producer // "absent"')"
if [ "$producer" != "absent" ]; then
  fail "expected no producer outside a run, got '$producer'"
else
  pass "omits the producer outside a run"
fi

# --- A non-Qase tool is not touched -----------------------------------------

other="$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' | run_hook)"
if [ -n "$other" ]; then
  fail "hook produced output for a non-Qase tool: $other"
else
  pass "ignores tools it does not own"
fi

# --- Malformed stdin is survivable ------------------------------------------

garbage="$(printf '%s' 'not json at all' | run_hook)"
status=$?
if [ "$status" -ne 0 ]; then
  fail "hook exited $status on malformed input; must always exit 0"
elif [ -n "$garbage" ]; then
  fail "hook produced output for malformed input: $garbage"
else
  pass "fails open on malformed input"
fi

# --- Empty stdin is survivable ----------------------------------------------

empty="$(printf '%s' '' | run_hook)"
if [ "$?" -ne 0 ] || [ -n "$empty" ]; then
  fail "hook did not fail open on empty input"
else
  pass "fails open on empty input"
fi

# --- A skill activation opens a run; seq increments per call ----------------

shared_tmp="$(mktemp -d)"
hook_in_shared() { TMPDIR="$shared_tmp" node "$HOOK"; }

printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s2","tool_name":"Skill","tool_input":{"skill":"quality-supervisor:analyzing-test-coverage"}}' | hook_in_shared > /dev/null

first="$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s2","tool_name":"mcp__qase__qase_qql","tool_input":{"query":"x"}}' | hook_in_shared)"
second="$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s2","tool_name":"mcp__qase__qase_qql","tool_input":{"query":"y"}}' | hook_in_shared)"

p1="$(echo "$first"  | jq -r '.hookSpecificOutput.updatedInput._qase_producer // empty')"
p2="$(echo "$second" | jq -r '.hookSpecificOutput.updatedInput._qase_producer // empty')"

if [ "$p1" != "analyzing-test-coverage/1/skill" ]; then
  fail "first call producer was '$p1', expected 'analyzing-test-coverage/1/skill'"
else
  pass "opens a run and strips the plugin prefix"
fi
if [ "$p2" != "analyzing-test-coverage/2/skill" ]; then
  fail "second call producer was '$p2', expected seq 2"
else
  pass "increments seq within a run"
fi

# --- Stop closes the run -----------------------------------------------------

printf '%s' '{"hook_event_name":"Stop","session_id":"s2"}' | hook_in_shared > /dev/null
after="$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s2","tool_name":"mcp__qase__qase_qql","tool_input":{"query":"z"}}' | hook_in_shared)"
p3="$(echo "$after" | jq -r '.hookSpecificOutput.updatedInput._qase_producer // "absent"')"
if [ "$p3" != "absent" ]; then
  fail "a call after Stop was attributed to '$p3'; the run must be closed"
else
  pass "Stop closes the run"
fi

# --- Another plugin's skill is not ours --------------------------------------

foreign_tmp="$(mktemp -d)"
printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s3","tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming"}}' | TMPDIR="$foreign_tmp" node "$HOOK" > /dev/null
foreign="$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s3","tool_name":"mcp__qase__qase_qql","tool_input":{"query":"q"}}' | TMPDIR="$foreign_tmp" node "$HOOK")"
pf="$(echo "$foreign" | jq -r '.hookSpecificOutput.updatedInput._qase_producer // "absent"')"
if [ "$pf" != "absent" ]; then
  fail "another plugin's skill was attributed to us as '$pf'"
else
  pass "ignores skills from other plugins"
fi

# --- A subagent does not share the parent's run ------------------------------

sub_tmp="$(mktemp -d)"
printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s4","tool_name":"Skill","tool_input":{"skill":"quality-supervisor:analyzing-test-flakiness"}}' | TMPDIR="$sub_tmp" node "$HOOK" > /dev/null
sub="$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s4","agent_id":"a99","tool_name":"mcp__qase__qase_qql","tool_input":{"query":"q"}}' | TMPDIR="$sub_tmp" node "$HOOK")"
ps="$(echo "$sub" | jq -r '.hookSpecificOutput.updatedInput._qase_producer // "absent"')"
if [ "$ps" != "absent" ]; then
  fail "a subagent inherited the parent's run as '$ps'; state must be keyed by agent_id too"
else
  pass "keys run state by session_id + agent_id"
fi

# --- A slash command opens a run named after the command --------------------

cmd_tmp="$(mktemp -d)"
printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"s5","prompt":"/quality-supervisor:quality-report WEB"}' | TMPDIR="$cmd_tmp" node "$HOOK" > /dev/null
cmd_call="$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s5","tool_name":"mcp__qase__qase_project_context","tool_input":{"code":"WEB"}}' | TMPDIR="$cmd_tmp" node "$HOOK")"
pc="$(echo "$cmd_call" | jq -r '.hookSpecificOutput.updatedInput._qase_producer // empty')"
if [ "$pc" != "quality-report/1/command" ]; then
  fail "command call producer was '$pc', expected 'quality-report/1/command'"
else
  pass "attributes pre-skill calls to the command"
fi

# --- A skill inside that command keeps the command entrypoint ---------------

printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s5","tool_name":"Skill","tool_input":{"skill":"quality-supervisor:analyzing-test-coverage"}}' | TMPDIR="$cmd_tmp" node "$HOOK" > /dev/null
in_cmd="$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s5","tool_name":"mcp__qase__qase_qql","tool_input":{"query":"q"}}' | TMPDIR="$cmd_tmp" node "$HOOK")"
pic="$(echo "$in_cmd" | jq -r '.hookSpecificOutput.updatedInput._qase_producer // empty')"
if [ "$pic" != "analyzing-test-coverage/1/command" ]; then
  fail "skill inside a command was '$pic', expected 'analyzing-test-coverage/1/command'"
else
  pass "keeps the command entrypoint for skills it launched"
fi

# --- A prompt that is not our command does not open a run -------------------

other_tmp="$(mktemp -d)"
printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"s6","prompt":"/gsd:help"}' | TMPDIR="$other_tmp" node "$HOOK" > /dev/null
oc="$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s6","tool_name":"mcp__qase__qase_qql","tool_input":{"query":"q"}}' | TMPDIR="$other_tmp" node "$HOOK" | jq -r '.hookSpecificOutput.updatedInput._qase_producer // "absent"')"
if [ "$oc" != "absent" ]; then
  fail "another plugin's command opened a run as '$oc'"
else
  pass "ignores commands from other plugins"
fi

# --- The agent attributes its own pre-skill calls ---------------------------

agent_tmp="$(mktemp -d)"
pa="$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s7","agent_id":"a1","agent_type":"quality-supervisor","tool_name":"mcp__qase__qase_project_context","tool_input":{"code":"WEB"}}' | TMPDIR="$agent_tmp" node "$HOOK" | jq -r '.hookSpecificOutput.updatedInput._qase_producer // empty')"
if [ "$pa" != "quality-supervisor/1/agent" ]; then
  fail "agent call producer was '$pa', expected 'quality-supervisor/1/agent'"
else
  pass "attributes the agent's own calls"
fi

# --- A skill run by our agent reports the agent entrypoint ------------------

printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s7","agent_id":"a1","agent_type":"quality-supervisor","tool_name":"Skill","tool_input":{"skill":"quality-supervisor:triaging-test-failures"}}' | TMPDIR="$agent_tmp" node "$HOOK" > /dev/null
pas="$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s7","agent_id":"a1","agent_type":"quality-supervisor","tool_name":"mcp__qase__qase_qql","tool_input":{"query":"q"}}' | TMPDIR="$agent_tmp" node "$HOOK" | jq -r '.hookSpecificOutput.updatedInput._qase_producer // empty')"
if [ "$pas" != "triaging-test-failures/1/agent" ]; then
  fail "skill inside our agent was '$pas', expected 'triaging-test-failures/1/agent'"
else
  pass "marks skills run by our agent as agent-entrypoint"
fi

# --- A third-party agent running our skill is still 'skill' -----------------

gp_tmp="$(mktemp -d)"
printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s8","agent_id":"a2","agent_type":"general-purpose","tool_name":"Skill","tool_input":{"skill":"quality-supervisor:analyzing-test-coverage"}}' | TMPDIR="$gp_tmp" node "$HOOK" > /dev/null
pgp="$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s8","agent_id":"a2","agent_type":"general-purpose","tool_name":"mcp__qase__qase_qql","tool_input":{"query":"q"}}' | TMPDIR="$gp_tmp" node "$HOOK" | jq -r '.hookSpecificOutput.updatedInput._qase_producer // empty')"
if [ "$pgp" != "analyzing-test-coverage/1/skill" ]; then
  fail "third-party agent gave '$pgp', expected entrypoint 'skill'"
else
  pass "a third-party agent running our skill is still skill-entrypoint"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "All mark-run checks passed."
