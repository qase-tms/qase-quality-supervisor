#!/bin/bash
#
# Claude Code reads .mcp.json and expands ${QASE_MCP_URL:-default} in it; Codex
# reads .mcp.codex.json and expands nothing, so a variable there becomes the
# literal URL. The two files must agree on the server name (the guard hooks
# match by it) and on the default endpoint.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."

failures=0
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }
pass() { echo "PASS: $1"; }

read_server() {   # prints "<name> <url>" for the single server in $1
  /usr/bin/python3 -c "
import json, sys, io
s = json.load(io.open(sys.argv[1], encoding='utf-8'))['mcpServers']
for name, cfg in s.items():
    print(name, cfg.get('url', ''))
" "$1"
}

read -r claude_name claude_url <<<"$(read_server "$ROOT/.mcp.json")"
read -r codex_name codex_url <<<"$(read_server "$ROOT/.mcp.codex.json")"

[ "$claude_name" = "qase" ] && pass ".mcp.json names the server qase" \
  || fail ".mcp.json names the server '$claude_name', the guard hooks expect qase"
[ "$codex_name" = "qase" ] && pass ".mcp.codex.json names the server qase" \
  || fail ".mcp.codex.json names the server '$codex_name', the guard hooks expect qase"

expected='${QASE_MCP_URL:-'"$codex_url"'}'
[ "$claude_url" = "$expected" ] && pass ".mcp.json defaults QASE_MCP_URL to the Codex endpoint" \
  || fail ".mcp.json url is '$claude_url', expected '$expected'"

case "$codex_url" in
  *'$'*) fail ".mcp.codex.json url '$codex_url' uses a variable, which Codex leaves unexpanded" ;;
  https://*) pass ".mcp.codex.json url is a literal https endpoint" ;;
  *) fail ".mcp.codex.json url '$codex_url' is not an https endpoint" ;;
esac

declared="$(/usr/bin/python3 -c "
import json, io
print(json.load(io.open('$ROOT/.codex-plugin/plugin.json', encoding='utf-8')).get('mcpServers',''))
")"
[ "$declared" = "./.mcp.codex.json" ] && pass ".codex-plugin/plugin.json declares ./.mcp.codex.json" \
  || fail ".codex-plugin/plugin.json declares mcpServers '$declared', expected ./.mcp.codex.json"

[ "$failures" -eq 0 ] || exit 1
