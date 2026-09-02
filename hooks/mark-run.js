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

  if (payload.hook_event_name !== 'PreToolUse') return;
  if (!QASE_TOOL.test(payload.tool_name || '')) return;

  const toolInput = { ...(payload.tool_input || {}) };
  toolInput._qase_integration = `quality-supervisor/${pluginVersion()}`;

  emitUpdatedInput(toolInput);
}

try {
  main();
} catch {
  // Fail open: no output means the tool input is used unchanged.
}
process.exit(0);
