#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Validating marketplace manifest"
claude plugin validate . --strict

echo "==> Validating plugin manifest + hooks"
claude plugin validate .claude-plugin/plugin.json --strict

echo "==> Secrets scan (literal QASE_API_TOKEN values in JSON files)"
if grep -rnE '"QASE_API_TOKEN"[[:space:]]*:[[:space:]]*"[^$][^"]{9,}"' --include='*.json' .; then
  echo "FAIL: a JSON file appears to contain a literal QASE_API_TOKEN value instead of \${QASE_API_TOKEN}. See match above." >&2
  exit 1
fi
echo "no literal token found"

echo "==> Installing the plugin from this repo as a local marketplace"
claude plugin marketplace add "$REPO_ROOT" >/dev/null
cleanup() {
  claude plugin uninstall quality-supervisor@quality-supervisor -y >/dev/null 2>&1 || true
  claude plugin marketplace remove quality-supervisor >/dev/null 2>&1 || true
}
trap cleanup EXIT

claude plugin install quality-supervisor@quality-supervisor >/dev/null

echo "==> Checking component inventory"
details="$(claude plugin details quality-supervisor)"
echo "$details"

if ! echo "$details" | grep -qE 'Skills \(5\)'; then
  echo "FAIL: expected 5 skills (coverage-gap-analysis, failure-triage, flakiness-stability, release-readiness, quality-report), got:" >&2
  echo "$details" | grep 'Skills' >&2
  exit 1
fi
if ! echo "$details" | grep -qE 'Agents \(1\)'; then
  echo "FAIL: expected 1 agent (quality-supervisor)." >&2
  exit 1
fi
if ! echo "$details" | grep -qE 'Hooks \(1\)'; then
  echo "FAIL: expected 1 hook (the destructive-call deny guard)." >&2
  exit 1
fi

echo "==> All checks passed"
