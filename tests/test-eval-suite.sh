#!/bin/bash
# A skill with no eval case is a skill whose routing nobody checks, and a grader
# naming a skill that no longer exists passes forever without asserting anything.
# Neither shows up in a run's score, so both are caught here instead — free, and
# in the blocking job.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
EVALS_DIR="$REPO_ROOT/evals"

failures=0
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

if [ ! -d "$EVALS_DIR" ]; then
  fail "evals/ is missing; the behaviour suite is part of the plugin"
  exit 1
fi

# Every skill is the target of at least one POSITIVE grader. A negative grader
# ("this skill must not fire", max: 0) mentions the skill too, and counting it
# would let a skill lose its own case while still looking covered.
for skill_md in "$SKILLS_DIR"/*/SKILL.md; do
  skill="$(basename "$(dirname "$skill_md")")"
  covered=false
  for grader in "$EVALS_DIR"/*/graders/*.md; do
    [ -e "$grader" ] || continue
    grep -q "$skill" "$grader" || continue
    grep -qE '^max:[[:space:]]*0' "$grader" && continue
    covered=true
    break
  done
  if [ "$covered" = false ]; then
    fail "no positive eval grader targets the skill '$skill'; its routing is unchecked"
  fi
done

# Every skill named in an input_match still exists. Only hyphenated tokens are
# considered: that is what a skill name looks like, and the surrounding regex
# syntax contains none.
for grader in "$EVALS_DIR"/*/graders/*.md; do
  [ -e "$grader" ] || continue
  while read -r named; do
    [ -n "$named" ] || continue
    if [ ! -d "$SKILLS_DIR/$named" ]; then
      fail "$(basename "$(dirname "$(dirname "$grader")")")/$(basename "$grader") names the skill '$named', which does not exist under skills/"
    fi
  done < <(grep -h '^input_match:' "$grader" | grep -oE '[a-z]+(-[a-z]+)+' | sort -u)
done

# Every case has a prompt and at least one grader.
for case_dir in "$EVALS_DIR"/*/; do
  case_name="$(basename "$case_dir")"
  case "$case_name" in mocks|results) continue ;; esac
  if [ ! -s "$case_dir/prompt.md" ] && [ ! -s "$case_dir/case.yaml" ]; then
    fail "case '$case_name' has neither a prompt.md nor a case.yaml"
  fi
  if ! ls "$case_dir"graders/*.md >/dev/null 2>&1; then
    fail "case '$case_name' has no graders; it would score nothing"
  fi
done

# The shared project mock is the seed every case reads first. If its suite
# tree contradicts what it claims (a suites.total that doesn't match the
# number of suites it actually lists), or drops the fourth "Payments" suite a
# fixture promises exists, cases built on top of it silently disagree with
# their own seed. Catch that here rather than case by case.
MOCK_CONTEXT="$EVALS_DIR/mocks/qase/qase_project_context.md"
if [ -f "$MOCK_CONTEXT" ]; then
  mock_json="$(grep -m1 '^{' "$MOCK_CONTEXT")"
  if [ -n "$mock_json" ]; then
    suites_total="$(echo "$mock_json" | jq -r '.suites.total // empty' 2>/dev/null)"
    suites_count="$(echo "$mock_json" | jq -r '.suites.entities | length' 2>/dev/null)"
    if [ -z "$suites_total" ] || [ -z "$suites_count" ]; then
      fail "mocks/qase/qase_project_context.md: could not read suites.total / suites.entities from the seed JSON"
    elif [ "$suites_total" != "$suites_count" ]; then
      fail "mocks/qase/qase_project_context.md: suites.total ($suites_total) does not equal the number of suite entries it lists ($suites_count)"
    fi
  else
    fail "mocks/qase/qase_project_context.md: no JSON body found to check suite counts against"
  fi

  mock_has_payments=false
  grep -q "Payments" "$MOCK_CONTEXT" && mock_has_payments=true
  for fixture in "$EVALS_DIR"/*/mocks/qase/qql_search.md; do
    [ -e "$fixture" ] || continue
    if grep -q "fourth suite" "$fixture" && [ "$mock_has_payments" = false ]; then
      fail "$fixture mentions a 'fourth suite' but mocks/qase/qase_project_context.md lists no suite named Payments"
    fi
  done
fi

# A recording pins an answer forever; if it tells the skill the project is
# empty while the shared mock reports 12 cases, 4 defects and 7 runs, the
# fixture and the replay disagree and whichever loses is undefined. None of
# these three bare, unfiltered project-wide queries should ever be recorded
# as returning nothing.
for rec in "$EVALS_DIR"/*/mocks/.replay/qase/*.json; do
  [ -e "$rec" ] || continue
  query="$(jq -r '.input.query // empty' "$rec" 2>/dev/null)"
  case "$query" in
    'entity = "case" and project = "DEMO"' | 'entity = "defect" and project = "DEMO"' | 'entity = "run" and project = "DEMO"')
      clean_output="$(jq -r '.output' "$rec" 2>/dev/null | sed -e '1{/^```/d;}' -e '$ {/^```$/d;}')"
      total="$(echo "$clean_output" | jq -r '.total // empty' 2>/dev/null)"
      if [ "$total" = "0" ]; then
        fail "$rec pins '$query' to total:0, contradicting the shared mock's non-empty DEMO project"
      fi
      ;;
  esac
done

if [ "$failures" -gt 0 ]; then exit 1; fi
echo "Every skill has an eval case, and every grader names a skill that exists."
