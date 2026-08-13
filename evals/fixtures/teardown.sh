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

if [ ! -f "$STATE" ]; then
  echo "no state.json — nothing was recorded, so nothing to remove." >&2
  echo "If fixtures exist anyway, find them by title prefix: [QS-TEST]" >&2
  exit 1
fi

P="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("project") or "DEVX")' "$STATE")"
read_id() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2]) or "")' "$STATE" "$1"; }

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
echo "done — state.json removed"
echo
echo "Verify nothing remains:"
echo '  entity = "case" and project = "'"$P"'" and title ~ "QS-TEST"   -> expect total 0'
