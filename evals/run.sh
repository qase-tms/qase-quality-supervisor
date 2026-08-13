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

run_layer() {
  local name="$1" out
  out="$("$name")" || true
  printf '%s\n' "$out"
  local p f
  p="$(printf '%s\n' "$out" | grep -c '^  PASS ' || true)"
  f="$(printf '%s\n' "$out" | grep -c '^  FAIL ' || true)"
  printf '\n%s: %s passed, %s failed\n' "$name" "$p" "$f"
  [ "$f" -eq 0 ]
}

case "${1:-}" in
  layer1) run_layer layer1 ;;
  *) echo "usage: $0 layer1" >&2; exit 64 ;;
esac
