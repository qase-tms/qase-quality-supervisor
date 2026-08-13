#!/bin/bash
#
# Seeds the Layer 3 fixtures. Idempotent: reuses anything already present.
#
# WRITES TO A REAL PROJECT. Every entity is titled with a "[QS-TEST]" prefix and
# confined to its own suite so it is identifiable and removable. Run
# teardown.sh when you are done — do not leave fixtures sitting in a project
# the team uses.
#
set -euo pipefail
: "${QASE_API_TOKEN:?export QASE_API_TOKEN first}"
P="${QS_EVAL_PROJECT:-DEVX}"
API="https://api.qase.io/v1"
STATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state.json"

post() { curl -s -H "Token: $QASE_API_TOKEN" -H "Content-Type: application/json" -X POST "$API/$1" -d "$2"; }
get()  { curl -s -H "Token: $QASE_API_TOKEN" "$API/$1"; }
urlenc() { python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$1"; }

# Extract result.<key>, printing nothing if the call failed.
res() { python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit()
if not d.get("status"): print("",end=""); sys.exit()
print((d.get("result") or {}).get(sys.argv[1]) or "")' "$1"; }

echo "==> suite"
suite_id="$(get "suite/$P?limit=100&search=$(urlenc '[QS-TEST]')" | python3 -c '
import json,sys
d=json.load(sys.stdin)
for e in (d.get("result") or {}).get("entities",[]):
    if str(e.get("title","")).startswith("[QS-TEST]"):
        print(e["id"]); break
')"
if [ -z "$suite_id" ]; then
  suite_id="$(post "suite/$P" '{"title":"[QS-TEST] fixtures","description":"Quality Supervisor eval fixtures. Safe to delete."}' | res id)"
  echo "    created suite $suite_id"
else
  echo "    reusing suite $suite_id"
fi
[ -n "$suite_id" ] || { echo "FAIL: could not create or find the fixture suite" >&2; exit 1; }

mkcase() {
  local title="$1" existing
  existing="$(get "case/$P?limit=100&search=$(urlenc "$title")" | python3 -c '
import json,sys
d=json.load(sys.stdin); t=sys.argv[1]
for e in (d.get("result") or {}).get("entities",[]):
    if e.get("title")==t: print(e["id"]); break
' "$title")"
  if [ -n "$existing" ]; then echo "$existing"; return; fi
  post "case/$P" "{\"title\":\"$title\",\"suite_id\":$suite_id,\"description\":\"Quality Supervisor eval fixture\"}" | res id
}

flaky_id="$(mkcase '[QS-TEST] flaky-case')"
broken_id="$(mkcase '[QS-TEST] broken-case')"
never_id="$(mkcase '[QS-TEST] never-run')"
echo "==> cases: flaky=$flaky_id broken=$broken_id never-run=$never_id"
for v in "$flaky_id" "$broken_id" "$never_id"; do
  [ -n "$v" ] || { echo "FAIL: a fixture case was not created" >&2; exit 1; }
done

# Reuse an existing fixture run if state.json already names one, so repeated
# seeds don't pile up runs (a run's title is not unique, so we can't search it).
run_id=""
if [ -f "$STATE" ]; then
  run_id="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("run_id") or "")' "$STATE" 2>/dev/null || true)"
  if [ -n "$run_id" ] && [ -z "$(get "run/$P/$run_id" | res id)" ]; then run_id=""; fi
fi

if [ -z "$run_id" ]; then
  echo "==> run with mixed results"
  run_id="$(post "run/$P" "{\"title\":\"[QS-TEST] mixed run\",\"description\":\"eval fixture\",\"cases\":[$flaky_id,$broken_id]}" | res id)"
  [ -n "$run_id" ] || { echo "FAIL: could not create the fixture run" >&2; exit 1; }
  # The discrimination the whole layer exists to test: the flaky case both
  # passes and fails; the broken case only ever fails.
  for st in passed failed passed failed; do
    post "result/$P/$run_id" "{\"case_id\":$flaky_id,\"status\":\"$st\"}" >/dev/null
  done
  for st in failed failed failed; do
    post "result/$P/$run_id" "{\"case_id\":$broken_id,\"status\":\"$st\",\"stacktrace\":\"AssertionError: expected 200, got 500\"}" >/dev/null
  done
  echo "    created run $run_id with 4 flaky-case results and 3 broken-case results"
else
  echo "==> reusing run $run_id"
fi

defect_id=""
if [ -f "$STATE" ]; then
  defect_id="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("defect_id") or "")' "$STATE" 2>/dev/null || true)"
  if [ -n "$defect_id" ] && [ -z "$(get "defect/$P/$defect_id" | res id)" ]; then defect_id=""; fi
fi
if [ -z "$defect_id" ]; then
  echo "==> blocking defect"
  defect_id="$(post "defect/$P" '{"title":"[QS-TEST] blocker","actual_result":"Quality Supervisor eval fixture - must force a NO-GO","severity":1}' | res id)"
  [ -n "$defect_id" ] || { echo "FAIL: could not create the fixture defect" >&2; exit 1; }
  echo "    created defect $defect_id"
else
  echo "==> reusing defect $defect_id"
fi

python3 - "$STATE" "$suite_id" "$flaky_id" "$broken_id" "$never_id" "$run_id" "$defect_id" <<'PY'
import json,sys
p,s,f,b,n,r,d = sys.argv[1:8]
json.dump({"project": __import__("os").environ.get("QS_EVAL_PROJECT","DEVX"),
           "suite_id":int(s),"flaky_case_id":int(f),"broken_case_id":int(b),
           "never_run_case_id":int(n),"run_id":int(r),"defect_id":int(d)},
          open(p,"w"), indent=2)
print("wrote", p)
PY

echo
echo "Fixtures ready in $P. Run evals/fixtures/teardown.sh when finished."
