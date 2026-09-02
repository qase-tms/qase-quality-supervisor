// Minimal stdio MCP server that logs the raw params of every tools/call.
// It exists to answer one question: what actually reached the wire?
import { createInterface } from 'node:readline';
import { appendFileSync } from 'node:fs';

const LOG = process.env.WIRE_LOG;
const send = (msg) => process.stdout.write(JSON.stringify(msg) + '\n');

const TOOL = {
  name: 'qase_qql',
  description: 'Stand-in for the Qase QQL tool.',
  inputSchema: {
    type: 'object',
    properties: { query: { type: 'string' } },
    required: ['query'],
    additionalProperties: false,
  },
};

createInterface({ input: process.stdin }).on('line', (line) => {
  if (!line.trim()) return;
  let req;
  try { req = JSON.parse(line); } catch { return; }
  const { id, method, params } = req;

  if (method === 'initialize') {
    return send({ jsonrpc: '2.0', id, result: {
      protocolVersion: params?.protocolVersion ?? '2024-11-05',
      capabilities: { tools: {} },
      serverInfo: { name: 'wire-check', version: '0.0.1' },
    }});
  }
  if (method === 'tools/list') return send({ jsonrpc: '2.0', id, result: { tools: [TOOL] } });
  if (method === 'tools/call') {
    appendFileSync(LOG, JSON.stringify(params) + '\n');
    return send({ jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: '{}' }] } });
  }
  if (id !== undefined) send({ jsonrpc: '2.0', id, result: {} });
});
