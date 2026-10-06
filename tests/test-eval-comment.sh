#!/bin/bash
# The comment is what a reviewer reads instead of the artifact, so it has to
# survive the runs that go wrong: a suite that died before writing an aggregate,
# a truncated file, a case that failed. None of those may take the step down with
# them — a job that fails while reporting a failure reports nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENDER="$SCRIPT_DIR/../scripts/eval-comment.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

failures=0
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

contains() {
  case "$2" in
    *"$1"*) : ;;
    *) fail "$3" ;;
  esac
}

cat > "$WORK/green.json" <<'JSON'
{
  "partial": false,
  "aggregates": { "casesTotal": 2, "casesPassed": 2, "overallScore": 1, "overallPassRate": 1 },
  "cases": [
    { "name": "alpha", "aggregates": { "score": 1, "passRate": 1 },
      "arms": { "with": [ { "graders": [ { "name": "skill-fired", "passed": true, "explanation": "ok" } ] } ] } },
    { "name": "beta", "aggregates": { "score": 1, "passRate": 1 },
      "arms": { "with": [ { "graders": [ { "name": "skill-fired", "passed": true, "explanation": "ok" } ] } ] } }
  ]
}
JSON

cat > "$WORK/red.json" <<'JSON'
{
  "partial": false,
  "aggregates": { "casesTotal": 2, "casesPassed": 1, "overallScore": 0.75, "overallPassRate": 0.5 },
  "cases": [
    { "name": "alpha", "aggregates": { "score": 1, "passRate": 1 },
      "arms": { "with": [ { "graders": [ { "name": "skill-fired", "passed": true, "explanation": "ok" } ] } ] } },
    { "name": "beta", "aggregates": { "score": 0.5, "passRate": 0 },
      "arms": { "with": [ { "graders": [
        { "name": "skill-fired", "passed": true, "explanation": "ok" },
        { "name": "names-the-gaps", "passed": false, "explanation": "judge voted FAIL 2-1" } ] } ] } }
  ]
}
JSON

# The marker has to come first, or CI cannot find its own previous comment and
# posts a fresh one on every push.
out="$(bash "$RENDER" "$WORK/green.json" "https://example.com/run/1")"
case "$(printf '%s\n' "$out" | head -1)" in
  '<!-- eval-report -->') : ;;
  *) fail "the sticky marker must be the first line; got: $(printf '%s\n' "$out" | head -1)" ;;
esac

contains '2/2 cases passed' "$out" "the green summary must report the case tally"
contains '`alpha`' "$out" "every case belongs in the table, including the green ones"
contains 'https://example.com/run/1' "$out" "the run URL must survive into the comment"
case "$out" in
  *'Graders that failed'*) fail "a green run must not open a fold onto no failures" ;;
esac

out="$(bash "$RENDER" "$WORK/red.json" "https://example.com/run/2")"
contains '1/2 cases passed' "$out" "the red summary must report the case tally"
contains 'Graders that failed' "$out" "a red run must list the graders that said no"
contains 'names-the-gaps' "$out" "the failing grader must be named"
contains 'judge voted FAIL 2-1' "$out" "the grader's own explanation is the point of the fold"
case "$out" in
  *'skill-fired'*) fail "a grader that passed must not be listed as a failure" ;;
esac

# Three ways a run goes wrong before it can be summarised. Each must still
# produce a comment, and must exit 0 so the reporting step stays green.
for broken in missing empty garbage; do
  case "$broken" in
    missing) arg="$WORK/not-here.json" ;;
    empty)   : > "$WORK/empty.json"; arg="$WORK/empty.json" ;;
    garbage) printf 'this is not json' > "$WORK/garbage.json"; arg="$WORK/garbage.json" ;;
  esac
  out="$(bash "$RENDER" "$arg" "https://example.com/run/3")"
  rc=$?
  [ "$rc" -eq 0 ] || fail "a $broken aggregate must not fail the step; exit was $rc"
  case "$(printf '%s\n' "$out" | head -1)" in
    '<!-- eval-report -->') : ;;
    *) fail "a $broken aggregate must still carry the sticky marker" ;;
  esac
  contains 'https://example.com/run/3' "$out" "a $broken aggregate must still point at the run log"
done

# Called with nothing at all, the way a step that lost its variables would.
out="$(bash "$RENDER")"
[ $? -eq 0 ] || fail "no arguments must not fail the step"
contains 'eval-report' "$out" "even argumentless, the comment needs its marker"

# Spend stays out: this lands on a public pull request.
for f in "$WORK/green.json" "$WORK/red.json"; do
  out="$(bash "$RENDER" "$f" "https://example.com/run/4")"
  case "$out" in
    *'$'*) fail "the comment must not carry costs onto a public pull request" ;;
  esac
done

if [ "$failures" -gt 0 ]; then exit 1; fi
echo "eval-comment.sh renders a run, names what failed, and survives a broken one."
