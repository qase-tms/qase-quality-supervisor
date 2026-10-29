#!/bin/bash
#
# Claude Code reads .mcp.json, Codex reads .mcp.codex.json. Both must name the
# server qase (the guard hooks match by it) and point at the same literal URL:
# a variable in it lets the environment choose where the user's OAuth token
# goes, which the plugin directory policy rejects as a credential forward.
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

[ "$claude_url" = "$codex_url" ] && pass "both files point at the same endpoint" \
  || fail ".mcp.json url '$claude_url' differs from .mcp.codex.json url '$codex_url'"

for pair in ".mcp.json $claude_url" ".mcp.codex.json $codex_url"; do
  read -r file url <<<"$pair"
  case "$url" in
    *'$'*) fail "$file url '$url' uses a variable" ;;
    https://*) pass "$file url is a literal https endpoint" ;;
    *) fail "$file url '$url' is not an https endpoint" ;;
  esac
done

declared="$(/usr/bin/python3 -c "
import json, io
print(json.load(io.open('$ROOT/.codex-plugin/plugin.json', encoding='utf-8')).get('mcpServers',''))
")"
[ "$declared" = "./.mcp.codex.json" ] && pass ".codex-plugin/plugin.json declares ./.mcp.codex.json" \
  || fail ".codex-plugin/plugin.json declares mcpServers '$declared', expected ./.mcp.codex.json"

[ "$failures" -eq 0 ] || exit 1
