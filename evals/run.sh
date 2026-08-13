#!/bin/bash
#
# Quality Supervisor eval runner. Local use only — see evals/README.md.
#
#   ./evals/run.sh layer1   query correctness against the live Qase API
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
PROJECT="${QS_EVAL_PROJECT:-DEVX}"

require_token() {
  if [ -z "${QASE_API_TOKEN:-}" ]; then
    echo "FAIL: QASE_API_TOKEN is not set. This layer talks to the live Qase API." >&2
    echo "      export QASE_API_TOKEN=... and re-run." >&2
    exit 1
  fi
}

# Prints one PASS/FAIL line for one expectation. Never prints the token.
# Deliberately keeps no counters: it runs inside a `while read` fed by a pipe,
# which bash executes in a subshell, so any variable it incremented would be
# discarded. run_layer counts the printed lines instead.
check() {
  local expect="$1" label="$2" body="$3"
  local verdict
  verdict="$(printf '%s' "$body" | python3 -c '
import json,sys
raw=sys.stdin.read()
try: d=json.loads(raw)
except Exception: print("BAD unparseable response"); sys.exit()
if not d.get("status"):
    print("ERR " + str(d.get("errorMessage") or "")[:70]); sys.exit()
r=d.get("result")
if isinstance(r,list):
    # some endpoints (system_field) return a bare list
    print(f"OK {len(r)}"); sys.exit()
r=r or {}
# `filtered` is the filter-aware count on REST list endpoints; `total` there
# ignores the filters entirely, which is the exact trap the skills document.
# QQL responses carry only `total`.
n=r.get("filtered")
if n is None: n=r.get("total")
print(f"OK {n}")
')"
  local outcome="${verdict%% *}" detail="${verdict#* }"
  local ok=0
  case "$expect" in
    ok)         [ "$outcome" = "OK" ] && ok=1 ;;
    ok_nonzero) [ "$outcome" = "OK" ] && [ "${detail:-0}" != "0" ] && [ "${detail:-0}" != "None" ] && ok=1 ;;
    error)      [ "$outcome" = "ERR" ] && ok=1 ;;
  esac
  if [ "$ok" = 1 ]; then
    printf '  PASS  %-44s %s\n' "$label" "$detail"
  else
    printf '  FAIL  %-44s expected %s, got %s %s\n' "$label" "$expect" "$outcome" "$detail"
  fi
}

layer1() {
  require_token
  echo "== Layer 1: query correctness (project $PROJECT) =="
  tail -n +2 evals/layer1-queries/queries.tsv | while IFS=$'\t' read -r kind expect label q; do
    [ -z "${kind:-}" ] && continue
    local body enc
    if [ "$kind" = "qql" ]; then
      enc="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$q")"
      body="$(curl -s -H "Token: $QASE_API_TOKEN" "https://api.qase.io/v1/search?query=$enc&limit=1")"
    else
      body="$(curl -s -H "Token: $QASE_API_TOKEN" "https://api.qase.io/v1/$q")"
    fi
    check "$expect" "$label" "$body"
  done
}

# Runs one prompt headlessly with the plugin loaded and the Qase MCP tools
# blocked, then prints "<CLEAN|LEAK> <skill-that-fired|none>". Blocking the MCP
# tools and Bash keeps a run to ~40s and stops it doing real work — only the
# routing decision matters here. LEAK means a Qase tool ran anyway, which makes
# the verdict untrustworthy and every later case slow.
trigger_once() {
  local prompt="$1" trace workdir
  trace="$(mktemp)"
  # Run from an empty directory, not the plugin repo. With the repo as cwd the
  # agent can Grep and Read the SKILL.md files directly and answer from them —
  # which inflates the routing score, because a real user's project does not
  # contain the plugin's source. Measured: the same prompt routed correctly from
  # the repo (after grepping the skill files) and not at all from a clean cwd.
  workdir="$(mktemp -d)"
  # stdin comes from /dev/null deliberately: trigger_once is called from a
  # `while read` loop fed by a pipe, and claude would otherwise consume the
  # loop's stdin — eating the remaining case rows and running with no prompt.
  ( cd "$workdir" && claude -p "$prompt" --plugin-dir "$REPO_ROOT" \
    --disallowedTools "mcp__qase__qql_search" "mcp__qase__qase_project_context" "mcp__qase__qase_get" "mcp__qase__qase_api" "Bash" \
    --output-format stream-json --verbose ) > "$trace" 2>/dev/null < /dev/null
  rmdir "$workdir" 2>/dev/null || rm -rf "$workdir"
  python3 - "$trace" <<'PY'
import json,sys
skills=[]; mcp=[]
for line in open(sys.argv[1]):
    line=line.strip()
    if not line.startswith('{'): continue
    try: ev=json.loads(line)
    except Exception: continue
    m=ev.get('message')
    if not isinstance(m,dict): continue
    c=m.get('content')
    if not isinstance(c,list): continue
    for b in c:
        if not isinstance(b,dict) or b.get('type')!='tool_use': continue
        nm=b.get('name') or ''
        if nm.startswith('mcp__qase__'): mcp.append(nm)
        if nm=='Skill':
            i=b.get('input')
            if isinstance(i,dict): skills.append(str(i.get('skill') or ''))
print('LEAK' if mcp else 'CLEAN', (skills[0].split(':')[-1] if skills else 'none'))
PY
  rm -f "$trace"
}

layer2() {
  echo "== Layer 2: skill triggering =="
  local runs="${QS_EVAL_RUNS:-1}"
  # QS_EVAL_FILTER limits the pass to prompts containing a substring — used to
  # re-run a single failing case, which routing nondeterminism makes necessary.
  local filter="${QS_EVAL_FILTER:-}"
  tail -n +2 evals/layer2-triggering/cases.tsv | while IFS=$'\t' read -r kind expected prompt; do
    [ -z "${kind:-}" ] && continue
    if [ -n "$filter" ] && [[ "$prompt" != *"$filter"* ]]; then continue; fi
    local i=1
    while [ "$i" -le "$runs" ]; do
      local out leak got
      out="$(trigger_once "$prompt")"
      leak="${out%% *}"; got="${out#* }"
      if [ "$leak" = "LEAK" ]; then
        printf '  FAIL  %-52s MCP tools were not blocked - check the tool names\n' "${prompt:0:52}"
      elif [ "$got" = "$expected" ]; then
        printf '  PASS  %-52s %s\n' "${prompt:0:52}" "$got"
      else
        printf '  FAIL  %-52s expected %s, fired %s\n' "${prompt:0:52}" "$expected" "$got"
      fi
      i=$((i+1))
    done
  done
}

run_layer() {
  local name="$1" log
  log="$(mktemp)"
  # tee rather than capture: the agent layers take ~40s per case, so results
  # have to appear as they happen instead of after fifteen silent minutes.
  "$name" 2>&1 | tee "$log" || true
  local p f
  p="$(grep -c '^  PASS ' "$log" || true)"
  f="$(grep -c '^  FAIL ' "$log" || true)"
  printf '\n%s: %s passed, %s failed\n' "$name" "$p" "$f"
  rm -f "$log"
  [ "$f" -eq 0 ]
}

case "${1:-}" in
  layer1) run_layer layer1 ;;
  layer2) run_layer layer2 ;;
  *) echo "usage: $0 layer1|layer2" >&2; exit 64 ;;
esac
