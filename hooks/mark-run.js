#!/usr/bin/env node
'use strict';

//
// PreToolUse/Stop/UserPromptSubmit hook: attributes this plugin's Qase MCP calls.
//
// FAIL-OPEN BY DESIGN. This is telemetry: it must never block, alter or break a
// tool call. Every error path exits 0 and prints nothing, which leaves the tool
// input exactly as it was. Do NOT make this match hooks/deny-destructive.sh —
// that guard is deliberately fail-closed, and the two contracts are opposites.
//
// The plugin declares itself here rather than through a header in .mcp.json,
// because a header rides the whole MCP session and would tag every Qase call
// made while the plugin merely happens to be installed.
//

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const QASE_TOOL = /^mcp__qase__/;

const PLUGIN_PREFIX = 'quality-supervisor:';

const COMMAND_PREFIX = '/quality-supervisor:';

// Claude Code namespaces a plugin's agent the same way it namespaces its skills:
// "<plugin>:<agent>". Matching the prefix rather than a bare name is what makes
// entrypoint=agent possible at all, and it keeps working if this plugin ever
// ships a second agent. Returns the agent's own name, or null when the caller is
// not one of ours.
function ourAgentName(payload) {
  const type = payload.agent_type || '';
  return type.startsWith(PLUGIN_PREFIX) ? type.slice(PLUGIN_PREFIX.length) : null;
}

// Which part of the plugin is driving, when a skill is activated. A run started
// by our command or our agent keeps that entrypoint: the skill is how the work
// is done, the entrypoint is how the user asked for it.
function entrypointFor(payload, existing) {
  if (existing && existing.entrypoint === 'command') return 'command';
  if (ourAgentName(payload)) return 'agent';
  return 'skill';
}

function readState(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

function writeState(file, state) {
  try {
    fs.writeFileSync(file, JSON.stringify(state));
  } catch {
    // Fail open: an unwritable tmpdir costs attribution, never the call.
  }
}

function clearState(file) {
  try {
    fs.unlinkSync(file);
  } catch {
    // Already gone, or never written.
  }
}

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function pluginVersion() {
  const manifest = path.join(__dirname, '..', '.claude-plugin', 'plugin.json');
  return JSON.parse(fs.readFileSync(manifest, 'utf8')).version;
}

function statePath(payload) {
  const key = `${payload.session_id || 'none'}/${payload.agent_id || 'main'}`;
  const hash = crypto.createHash('sha1').update(key).digest('hex').slice(0, 16);
  return path.join(os.tmpdir(), `qase-qs-${hash}.json`);
}

function emitUpdatedInput(toolInput) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: { hookEventName: 'PreToolUse', updatedInput: toolInput },
    }),
  );
}

function main() {
  const payload = JSON.parse(readStdin());
  const event = payload.hook_event_name;
  const file = statePath(payload);

  if (event === 'Stop') {
    clearState(file);
    return;
  }

  if (event === 'UserPromptSubmit') {
    const prompt = (payload.prompt || '').trim();
    if (prompt.startsWith(COMMAND_PREFIX)) {
      const name = prompt.slice(COMMAND_PREFIX.length).split(/\s/)[0];
      if (name) writeState(file, { producer: name, entrypoint: 'command', seq: 0 });
    } else {
      // A new prompt that is not ours ends whatever run was open.
      clearState(file);
    }
    return;
  }

  if (event !== 'PreToolUse') return;

  if (payload.tool_name === 'Skill') {
    const skill = (payload.tool_input || {}).skill || '';
    if (skill.startsWith(PLUGIN_PREFIX)) {
      writeState(file, {
        producer: skill.slice(PLUGIN_PREFIX.length),
        entrypoint: entrypointFor(payload, readState(file)),
        seq: 0,
      });
    }
    return;
  }

  if (!QASE_TOOL.test(payload.tool_name || '')) return;

  const toolInput = { ...(payload.tool_input || {}) };
  toolInput._qase_integration = `quality-supervisor/${pluginVersion()}`;

  let state = readState(file);
  if (!state) {
    const agent = ourAgentName(payload);
    if (agent) state = { producer: agent, entrypoint: 'agent', seq: 0 };
  }
  if (state && state.producer) {
    state.seq = (state.seq || 0) + 1;
    writeState(file, state);
    toolInput._qase_producer = `${state.producer}/${state.seq}/${state.entrypoint}`;
  }

  emitUpdatedInput(toolInput);
}

try {
  main();
} catch {
  // Fail open: no output means the tool input is used unchanged.
}
process.exit(0);
