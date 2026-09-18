#!/bin/bash
# Behaviour tests for the plugin: does it route a natural request to the right
# skill and finish the analysis. Separate from verify-plugin.sh, which checks
# that the plugin is well-formed rather than that it works.
#
# The CLI is taken from CLAUDE_EVAL_BIN because `plugin eval` needs 2.1.269+,
# and the stable channel is still below that.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${CLAUDE_EVAL_BIN:-claude}"
MIN_VERSION="2.1.269"

SMOKE=false
DRY_RUN=false
CASE_GLOB=""
while [ $# -gt 0 ]; do
  case "$1" in
    --smoke)   SMOKE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --case)    CASE_GLOB="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2
       echo "Usage: $0 [--smoke] [--dry-run] [--case <glob>]" >&2
       exit 1 ;;
  esac
done

if ! command -v "$CLI" >/dev/null 2>&1 && [ ! -x "$CLI" ]; then
  echo "FAIL: no Claude Code CLI at '$CLI'. Set CLAUDE_EVAL_BIN to one, or install claude on PATH." >&2
  exit 1
fi

version="$("$CLI" --version 2>/dev/null | cut -d' ' -f1)"
lowest="$(printf '%s\n%s\n' "$MIN_VERSION" "$version" | sort -V | head -1)"
if [ "$lowest" != "$MIN_VERSION" ]; then
  echo "FAIL: 'claude plugin eval' needs $MIN_VERSION or later; '$CLI' is $version." >&2
  echo "The stable channel is behind. Install it beside your own CLI and point CLAUDE_EVAL_BIN at it:" >&2
  echo "  npm install --prefix /tmp/eval-cli @anthropic-ai/claude-code@2.1.276" >&2
  echo "  export CLAUDE_EVAL_BIN=/tmp/eval-cli/node_modules/.bin/claude" >&2
  exit 1
fi

args=(plugin eval "$REPO_ROOT" --trust-plugin --no-publish
      --model claude-sonnet-5 --judge-model claude-haiku-4-5)

if [ "$SMOKE" = true ]; then
  # What runs on every PR: no baseline arm, one run per case, hard pass bar.
  args+=(--tag smoke --ablation none --runs 1 --threshold 1.0 --max-cost-usd 5)
else
  # The full sweep: both arms, three runs each, so the delta means something.
  args+=(--ablation with-without --runs 3 --threshold 0.8 --max-cost-usd 40 --scaffold)
fi

[ -n "$CASE_GLOB" ] && args+=(--case "$CASE_GLOB")

if [ "$DRY_RUN" = true ]; then
  echo "$CLI ${args[*]}"
  exit 0
fi

exec "$CLI" "${args[@]}"
