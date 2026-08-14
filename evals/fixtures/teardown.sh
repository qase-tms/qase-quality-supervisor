#!/bin/bash
#
# Removes the Layer 3 fixtures recorded in state.json.
#
# This calls DELETE endpoints over REST, deliberately. It is a maintenance
# script, not something a skill can reach: the plugin's PreToolUse guard still
# blocks the model from deleting anything in Qase, which is itself under test
# elsewhere in this repo.
#
set -uo pipefail
: "${QASE_API_TOKEN:?export QASE_API_TOKEN first}"
API="https://api.qase.io/v1"
STATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state.json"

# A missing state.json is not a reason to stop: orphaned fixtures are exactly
# the case the prefix sweep at the end exists for, and it needs no state.
if [ -f "$STATE" ]; then
  P="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("project") or "DEVX")' "$STATE")"
  read_id() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2]) or "")' "$STATE" "$1"; }
else
  echo "no state.json — skipping the recorded IDs, sweeping by title prefix only" >&2
  P="${QS_EVAL_PROJECT:-DEVX}"
  read_id() { echo ""; }
fi

del() {
  local path="$1" code
  code="$(curl -s -o /dev/null -w '%{http_code}' -X DELETE -H "Token: $QASE_API_TOKEN" "$API/$path")"
  if [ "$code" = "200" ]; then
    echo "    deleted $path"
  else
    echo "    WARN  $path -> HTTP $code (may already be gone)"
  fi
}

echo "==> removing [QS-TEST] fixtures from $P"

# Results go with the run, so the run is removed first; the suite last, once
# the cases it holds are gone.
id="$(read_id run_id)";    [ -n "$id" ] && del "run/$P/$id"
id="$(read_id defect_id)"; [ -n "$id" ] && del "defect/$P/$id"
for k in flaky_case_id broken_case_id never_run_case_id; do
  id="$(read_id "$k")"; [ -n "$id" ] && del "case/$P/$id"
done
id="$(read_id suite_id)";  [ -n "$id" ] && del "suite/$P/$id"

rm -f "$STATE"

# Sweep by title prefix as well as by state.json. state.json only knows what the
# last seed recorded, so a fixture created by a run whose state file was replaced
# or lost is invisible to the loop above — that happened once, leaving a
# `[QS-TEST] blocker` defect sitting in a real project. Orphans are what this
# catches.
echo "==> sweeping for orphaned [QS-TEST] fixtures"
sweep() {
  local kind="$1" url="$2" ids
  ids="$(curl -s --max-time 30 -H "Token: $QASE_API_TOKEN" "$url" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit()
if not d.get("status"): sys.exit()
for e in (d.get("result") or {}).get("entities",[]):
    if str(e.get("title","")).startswith("[QS-TEST]"): print(e["id"])
' 2>/dev/null)"
  for id in $ids; do
    echo "    orphan $kind/$id"
    del "$kind/$P/$id"
  done
  [ -z "$ids" ] && echo "    no orphaned ${kind}s"
}
sweep defect "$API/defect/$P?limit=100"
sweep run    "$API/run/$P?limit=100"
sweep case   "$API/case/$P?limit=100&search=QS-TEST"
sweep suite  "$API/suite/$P?limit=100&search=QS-TEST"

echo "done"
