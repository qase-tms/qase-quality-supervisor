#!/bin/bash
# The runner is the only place that knows which flags a smoke run needs and
# which CLI may run it. Both are easy to get wrong silently: an old CLI answers
# "early access" and a missing --tag turns a cheap PR check into a full sweep.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/../scripts/run-evals.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

failures=0
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

# A stub CLI whose version we control.
make_stub() {
  cat > "$WORK/claude" <<STUB
#!/bin/bash
if [ "\$1" = "--version" ]; then echo "$1 (Claude Code)"; exit 0; fi
echo "STUB CALLED: \$*"
STUB
  chmod +x "$WORK/claude"
}

make_stub "2.1.267"
out="$(CLAUDE_EVAL_BIN="$WORK/claude" bash "$RUNNER" --smoke --dry-run 2>&1)"
if [ $? -eq 0 ]; then
  fail "a CLI below 2.1.269 must be refused, but the runner accepted it"
fi
case "$out" in
  *2.1.269*) : ;;
  *) fail "the refusal must name the required version so the reader knows what to install; got: $out" ;;
esac

make_stub "2.1.276"
out="$(CLAUDE_EVAL_BIN="$WORK/claude" bash "$RUNNER" --smoke --dry-run 2>&1)" || fail "2.1.276 must be accepted"
for flag in "--tag smoke" "--ablation none" "--runs 1" "--threshold 1.0" "--max-cost-usd 5" "--trust-plugin" "--no-publish" "--model claude-sonnet-5" "--judge-model claude-haiku-4-5"; do
  case "$out" in
    *"$flag"*) : ;;
    *) fail "smoke run is missing '$flag'; got: $out" ;;
  esac
done
case "$out" in
  *"STUB CALLED"*) fail "dry-run must print the command, not invoke the CLI; got: $out" ;;
esac

out="$(CLAUDE_EVAL_BIN="$WORK/claude" bash "$RUNNER" --dry-run 2>&1)" || fail "full run must be accepted"
case "$out" in
  *"--tag smoke"*) fail "a full run must not filter by the smoke tag; got: $out" ;;
esac
for flag in "--ablation with-without" "--model claude-sonnet-5" "--judge-model claude-haiku-4-5"; do
  case "$out" in
    *"$flag"*) : ;;
    *) fail "full run is missing '$flag'; got: $out" ;;
  esac
done
case "$out" in
  *"STUB CALLED"*) fail "dry-run must print the command, not invoke the CLI; got: $out" ;;
esac

if [ "$failures" -gt 0 ]; then exit 1; fi
echo "run-evals.sh dispatches the right flags on a supported CLI."
