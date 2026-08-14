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
# QS_EVAL_MODEL overrides the model for the agent layers. The authoring guide
# warns that a skill sufficient for a strong model can under-specify for a
# smaller one, so routing and execution need measuring per model rather than
# assumed from the session default.
MODEL_ARGS=()
[ -n "${QS_EVAL_MODEL:-}" ] && MODEL_ARGS=(--model "$QS_EVAL_MODEL")

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
    local body enc url attempt
    if [ "$kind" = "qql" ]; then
      enc="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$q")"
      url="https://api.qase.io/v1/search?query=$enc&limit=1"
    else
      url="https://api.qase.io/v1/$q"
    fi
    # Retry a non-JSON body once. The API occasionally returns an empty or
    # truncated response under load, and that is an infrastructure hiccup rather
    # than a broken query — without the retry it reads as a query regression and
    # sends you looking in the wrong place. A real query error still comes back
    # as well-formed JSON with status:false, so it is not masked by this.
    for attempt in 1 2; do
      body="$(curl -s --max-time 30 -H "Token: $QASE_API_TOKEN" "$url")"
      printf '%s' "$body" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null && break
      [ "$attempt" = 1 ] && sleep 2
    done
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
  ( cd "$workdir" && claude -p "$prompt" --plugin-dir "$REPO_ROOT" "${MODEL_ARGS[@]}" \
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
        # Task counts too: the plugin ships a quality-supervisor orchestrator
        # agent, and routing to it is a legitimate outcome. Scoring only Skill
        # invocations reports an agent hand-off as "none" — a false negative.
        if nm in ('Skill','Task'):
            i=b.get('input')
            if isinstance(i,dict):
                skills.append(str(i.get('skill') or i.get('subagent_type') or ''))
first = next((s for s in skills if s), '')
own = 'OURS' if (first.startswith('quality-supervisor') or first=='quality-supervisor') else ('FOREIGN' if first else 'NONE')
print('LEAK' if mcp else 'CLEAN', own, (first.split(':')[-1] if first else 'none'))
PY
  rm -f "$trace"
}

layer2() {
  echo "== Layer 2: skill triggering (model: ${QS_EVAL_MODEL:-session default}) =="
  local runs="${QS_EVAL_RUNS:-1}"
  # QS_EVAL_FILTER limits the pass to prompts containing a substring — used to
  # re-run a single failing case, which routing nondeterminism makes necessary.
  local filter="${QS_EVAL_FILTER:-}"
  tail -n +2 evals/layer2-triggering/cases.tsv | while IFS=$'\t' read -r kind expected prompt; do
    [ -z "${kind:-}" ] && continue
    if [ -n "$filter" ] && [[ "$prompt" != *"$filter"* ]]; then continue; fi
    local i=1
    while [ "$i" -le "$runs" ]; do
      local out leak foreign got
      out="$(trigger_once "$prompt")"
      leak="$(printf '%s' "$out" | cut -d' ' -f1)"
      foreign="$(printf '%s' "$out" | cut -d' ' -f2)"
      got="$(printf '%s' "$out" | cut -d' ' -f3)"
      if [ "$leak" = "LEAK" ]; then
        printf '  FAIL  %-52s MCP tools were not blocked - check the tool names\n' "${prompt:0:52}"
      elif [ "$got" = "$expected" ]; then
        printf '  PASS  %-52s %s\n' "${prompt:0:52}" "$got"
      elif [ "$got" != "none" ] && [ "$foreign" = "FOREIGN" ]; then
        # A skill from another installed plugin won the routing. That is
        # environmental, not a defect in these descriptions — the environment
        # this runs in has whatever else the developer installed. Reported
        # separately so it cannot be mistaken for one of our skills misfiring,
        # which is the failure that would actually invert a user's advice.
        printf '  WARN  %-52s another plugin fired: %s\n' "${prompt:0:52}" "$got"
      else
        printf '  FAIL  %-52s expected %s, fired %s\n' "${prompt:0:52}" "$expected" "$got"
      fi
      i=$((i+1))
    done
  done
}

# Layer 3's fixtures are written over REST, but the skills read them through
# QQL, whose index lags behind. Without this check a not-yet-indexed fixture
# looks exactly like a skill that failed to find it.
fixtures_indexed() {
  local flaky="$1" broken="$2" q enc n
  q="SELECT (caseId, status, COUNT(*)) entity = \"result\" and project = \"$PROJECT\" and caseId in ($flaky, $broken) GROUP BY caseId, status"
  enc="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$q")"
  n="$(curl -s -H "Token: $QASE_API_TOKEN" "https://api.qase.io/v1/search?query=$enc&limit=10" \
       | python3 -c 'import json,sys
d=json.load(sys.stdin)
print(len((d.get("result") or {}).get("entities",[])) if d.get("status") else 0)')"
  # three groups expected: flaky passed, flaky failed, broken failed
  [ "${n:-0}" -ge 3 ]
}

layer3() {
  require_token
  local state="evals/fixtures/state.json"
  if [ ! -f "$state" ]; then
    echo "  FAIL  no fixtures — run evals/fixtures/seed.sh first"
    return 0
  fi
  local flaky broken defect
  flaky="$(python3 -c 'import json;print(json.load(open("evals/fixtures/state.json"))["flaky_case_id"])')"
  broken="$(python3 -c 'import json;print(json.load(open("evals/fixtures/state.json"))["broken_case_id"])')"
  defect="$(python3 -c 'import json;print(json.load(open("evals/fixtures/state.json"))["defect_id"])')"

  if ! fixtures_indexed "$flaky" "$broken"; then
    echo "  FAIL  fixtures are not visible to QQL yet (the search index lags the REST"
    echo "        write that created them). Wait and re-run — this is not a skill defect."
    return 0
  fi

  echo "  (fixtures indexed: flaky=$flaky broken=$broken defect=$defect)"

  # A throwaway MCP config carrying the token. Written outside the repo with
  # owner-only permissions and removed on the way out — the token must never
  # land in a file the repo tracks.
  MCP_CFG="$(mktemp -t qs-eval-mcp)"
  chmod 600 "$MCP_CFG"
  trap 'rm -f "$MCP_CFG"' RETURN
  python3 - "$MCP_CFG" "$QASE_API_TOKEN" <<'PY'
import json,sys
json.dump({"mcpServers":{"qase":{"command":"npx","args":["-y","@qase/mcp-server"],
          "env":{"QASE_API_TOKEN":sys.argv[2]}}}}, open(sys.argv[1],"w"))
PY
  tail -n +2 evals/layer3-scenarios/cases.tsv | while IFS=$'\t' read -r label prompt want notwant; do
    [ -z "${label:-}" ] && continue
    want="${want//FLAKY_ID/$flaky}";     want="${want//BROKEN_ID/$broken}";     want="${want//DEFECT_ID/$defect}"
    notwant="${notwant//FLAKY_ID/$flaky}"; notwant="${notwant//BROKEN_ID/$broken}"; notwant="${notwant//DEFECT_ID/$defect}"
    local answer workdir bad=""
    workdir="$(mktemp -d)"
    # Same neutral-cwd rule as layer 2. MCP stays enabled here — this layer is
    # about what the methodology concludes from real data — but it has to be the
    # local token-based server: the shipped .mcp.json points at the hosted
    # OAuth endpoint, and a headless session cannot complete an OAuth flow.
    # The server is named `qase` so the plugin's destructive-call guard hook,
    # which matches on `mcp__qase__*`, applies exactly as it does in production.
    # The language is pinned because assertions are substring matches: a session
    # configured for another language will answer correctly in that language and
    # fail every English assertion. Learned the hard way — a skill that answered
    # "это регрессия, а не флаки", exactly right, failed on missing:'regression'.
    answer="$( cd "$workdir" && claude -p "$prompt" --plugin-dir "$REPO_ROOT" "${MODEL_ARGS[@]}" \
                 --mcp-config "$MCP_CFG" --strict-mcp-config \
                 --allowedTools "mcp__qase" \
                 --append-system-prompt "Answer in English, regardless of any other language preference." \
                 --output-format text 2>/dev/null < /dev/null )"
    rm -rf "$workdir"
    local IFS_SAVE="$IFS"
    IFS='|' read -ra wants <<< "$want"
    for w in "${wants[@]:-}"; do
      [ -z "$w" ] && continue
      printf '%s' "$answer" | grep -qiF -- "$w" || bad="$bad missing:'$w'"
    done
    IFS='|' read -ra nots <<< "$notwant"
    for n in "${nots[@]:-}"; do
      [ -z "$n" ] && continue
      printf '%s' "$answer" | grep -qiF -- "$n" && bad="$bad present:'$n'"
    done
    IFS="$IFS_SAVE"
    if [ -z "$bad" ]; then
      printf '  PASS  %-38s\n' "$label"
    else
      printf '  FAIL  %-38s%s\n' "$label" "$bad"
      printf '        excerpt: %s\n' "$(printf '%s' "$answer" | tr '\n' ' ' | cut -c1-220)"
    fi
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
  layer3) run_layer layer3 ;;
  all)
    ok=0
    run_layer layer1 || ok=1
    run_layer layer2 || ok=1
    run_layer layer3 || ok=1
    exit "$ok"
    ;;
  *) echo "usage: $0 layer1|layer2|layer3|all" >&2; exit 64 ;;
esac
