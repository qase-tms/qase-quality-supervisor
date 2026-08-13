#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

STATIC_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --static-only)
      STATIC_ONLY=true
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--static-only]" >&2
      exit 1
      ;;
  esac
done

# ---- Preflight --------------------------------------------------------------

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "FAIL: required command '$1' not found on PATH. Install it before running this script." >&2
    exit 1
  fi
}

require_cmd claude
require_cmd grep
require_cmd cut

# ---- Static checks (manifests, secrets, hook tests) -------------------------

echo "==> Validating marketplace manifest"
claude plugin validate . --strict

echo "==> Validating plugin manifest + hooks"
claude plugin validate .claude-plugin/plugin.json --strict

echo "==> Secrets scan (literal QASE_API_TOKEN values in JSON files)"
# Report only file/line — never the matched value, which would leak the
# literal token into CI logs. `cut -d: -f1,2` drops grep's captured content.
matches="$(grep -rnE '"QASE_API_TOKEN"[[:space:]]*:[[:space:]]*"[^$][^"]{9,}"' --include='*.json' . || true)"
if [ -n "$matches" ]; then
  echo "FAIL: a JSON file appears to contain a literal QASE_API_TOKEN value instead of \${QASE_API_TOKEN}. Value redacted; locations:" >&2
  printf '%s\n' "$matches" | cut -d: -f1,2 >&2
  exit 1
fi
echo "no literal token found"

echo "==> Compliance files present"
for f in LICENSE CHANGELOG.md; do
  if [ ! -f "$f" ]; then
    echo "FAIL: expected $f to exist at the repo root." >&2
    exit 1
  fi
done

echo "==> Destructive-call guards declared and executable"
# `claude plugin details` reports hook EVENTS, not matcher entries, so it
# cannot tell one guard from two. Assert both matchers and both scripts here,
# where it is actually observable.
for matcher in 'mcp__qase__\.\*delete\.\*' 'mcp__qase__qase_api'; do
  if ! grep -qE "\"matcher\"[[:space:]]*:[[:space:]]*\"${matcher}\"" hooks/hooks.json; then
    echo "FAIL: hooks/hooks.json does not declare a matcher for '${matcher//\\/}'." >&2
    exit 1
  fi
done
for hook in hooks/deny-destructive.sh hooks/deny-destructive-api.sh; do
  if [ ! -f "$hook" ]; then
    echo "FAIL: expected guard script $hook to exist." >&2
    exit 1
  fi
  if [ ! -x "$hook" ]; then
    echo "FAIL: guard script $hook is not executable." >&2
    exit 1
  fi
  if ! grep -qF "$hook" hooks/hooks.json; then
    echo "FAIL: $hook exists but is not referenced by hooks/hooks.json." >&2
    exit 1
  fi
done

echo "==> Running hook unit tests"
shopt -s nullglob
test_files=(tests/test-*.sh)
shopt -u nullglob
if [ "${#test_files[@]}" -eq 0 ]; then
  echo "FAIL: no test files matched tests/test-*.sh." >&2
  exit 1
fi
for test_file in "${test_files[@]}"; do
  echo "--- $test_file ---"
  bash "$test_file"
done

if [ "$STATIC_ONLY" = true ]; then
  echo "==> Static checks passed (--static-only: skipping install phase)"
  exit 0
fi

# ---- Install phase (marketplace add -> install -> inventory) ---------------
#
# cleanup()/trap are defined before the marketplace is touched so there is no
# window where a failure between "add" and "trap" could leak a registration.
# It also pre-cleans any leftover registration from a previous failed run,
# so this script is safely re-runnable.

cleanup() {
  claude plugin uninstall quality-supervisor@quality-supervisor -y >/dev/null 2>&1 || true
  claude plugin marketplace remove quality-supervisor >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Pre-cleaning any leftover quality-supervisor marketplace registration"
cleanup

echo "==> Installing the plugin from this repo as a local marketplace"
claude plugin marketplace add "$REPO_ROOT" >/dev/null
claude plugin install quality-supervisor@quality-supervisor >/dev/null

echo "==> Checking component inventory"
details="$(claude plugin details quality-supervisor)"
echo "$details"

if ! echo "$details" | grep -qE 'Skills \(5\)'; then
  echo "FAIL: expected 5 skills (coverage-gap-analysis, failure-triage, flakiness-stability, release-readiness, quality-report), got:" >&2
  echo "$details" | grep 'Skills' >&2 || true
  exit 1
fi

expected_skills=(
  coverage-gap-analysis
  failure-triage
  flakiness-stability
  release-readiness
  quality-report
)
for skill in "${expected_skills[@]}"; do
  if ! echo "$details" | grep -qF "$skill"; then
    echo "FAIL: expected skill '$skill' not found in plugin details output." >&2
    exit 1
  fi
done

if ! echo "$details" | grep -qE 'Agents \(1\)'; then
  echo "FAIL: expected 1 agent (quality-supervisor)." >&2
  exit 1
fi
# The CLI counts hook EVENTS, not matcher entries: both guards live under
# PreToolUse, so it reports "Hooks (1)  PreToolUse" regardless of how many
# matchers are declared. That confirms registration only — the two matchers
# themselves are asserted directly against hooks.json below.
if ! echo "$details" | grep -qE 'Hooks \(1\).*PreToolUse'; then
  echo "FAIL: expected a registered PreToolUse hook." >&2
  echo "$details" | grep 'Hooks' >&2 || true
  exit 1
fi

echo "==> All checks passed"
