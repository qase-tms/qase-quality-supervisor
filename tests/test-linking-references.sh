#!/bin/bash
# The linking skill writes syntax straight into users' code, and several reporter
# docs show forms that are silently ignored. These pins keep the verified forms
# from drifting back to the documented-but-wrong ones.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REFS="$REPO_ROOT/skills/linking-test-cases/references"

failures=0
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

has() { grep -qF -- "$2" "$REFS/$1" || fail "$1 is missing: $2"; }

# Body of one "### name" section.
section() { awk -v h="### $2" '/^### /{p=($0==h)} p' "$REFS/$1"; }

# macOS ships bash 3.2, which has no associative arrays.
frameworks_of() {
  case "$1" in
    javascript.md) echo "Jest|Playwright|Cypress|Cypress + Cucumber|Mocha|Vitest|WDIO (mocha/jasmine)|WDIO (cucumber)|TestCafe|Newman|CucumberJS" ;;
    python.md) echo "pytest|pytest-bdd|Robot Framework|Behave|Tavern" ;;
    jvm.md) echo "JUnit4|JUnit5|TestNG|Java Cucumber (v3-v7)|Kotlin JUnit4 / Android|Kaspresso" ;;
    dotnet.md) echo "NUnit|xUnit|xUnit v3|MSTest|Reqnroll" ;;
    go.md) echo "Go" ;;
    php.md) echo "PHPUnit|Pest|Codeception" ;;
  esac
}

for file in javascript.md python.md jvm.md dotnet.md go.md php.md; do
  if [ ! -f "$REFS/$file" ]; then
    fail "$file does not exist"
    continue
  fi
  IFS='|' read -ra names <<< "$(frameworks_of "$file")"
  for name in "${names[@]}"; do
    if ! grep -qxF "### $name" "$REFS/$file"; then
      fail "$file has no '### $name' section"
      continue
    fi
    body="$(section "$file" "$name")"
    for label in Detect Write Multi-ID "Never write"; do
      grep -qF "**$label:**" <<< "$body" || fail "$file / $name lacks **$label:**"
    done
  done
  grep -c '^### ' "$REFS/$file" | grep -qx "${#names[@]}" \
    || fail "$file has a different number of framework sections than expected (${#names[@]})"
  if [ "$(wc -l < "$REFS/$file")" -gt 100 ]; then
    grep -qxF '## Contents' "$REFS/$file" || fail "$file is over 100 lines and has no ## Contents"
  fi
done

[ -f "$REFS/javascript.md" ] && {
  has javascript.md 'addQaseId('
  section javascript.md Vitest | grep -F '**Never write:**' | grep -qF 'qase(' \
    || fail "javascript.md: Vitest Never write must name qase("
  has javascript.md '@QaseID(1)'
  has javascript.md '@QaseID=1'
  has javascript.md '(Qase ID: 1,2)'
}

[ -f "$REFS/jvm.md" ] && {
  has jvm.md '@QaseIds=1,2'
  if grep -F '@QaseId=1,2' "$REFS/jvm.md" | grep -qvF '**Never write:**'; then
    fail "jvm.md: @QaseId=1,2 appears outside a Never write line"
  fi
  grep -qF '@QaseId=1,2' "$REFS/jvm.md" || fail "jvm.md: @QaseId=1,2 is not listed as a never-write form"
}

[ -f "$REFS/dotnet.md" ] && {
  has dotnet.md '[QaseIds(123)]'
  has dotnet.md '@QaseId:1,2'
  has dotnet.md 'last one wins'
}

[ -f "$REFS/php.md" ] && {
  has php.md 'qase()->caseId('
  section php.md Pest | grep -F '**Never write:**' | grep -qF '#[QaseId]' \
    || fail "php.md: Pest Never write must name #[QaseId]"
}

[ -f "$REFS/python.md" ] && {
  has python.md '@qase.id:1'
  has python.md '@qase.id=1'
  has python.md 'Q-1'
  has python.md 'parametrize'
}

[ -f "$REFS/go.md" ] && {
  has go.md 'QaseIDs: []int64{'
  has go.md 'report only'
}

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "OK: linking references"
