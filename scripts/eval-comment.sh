#!/bin/bash
# Renders an eval run into the markdown that CI posts back to the pull request.
# A red check tells you the suite failed; this tells you which case fell over and
# which grader said so, without downloading the artifact and opening the HTML.
#
# Usage: eval-comment.sh <aggregate-result.json> <run-url>
# A missing or unreadable aggregate is not an error: the suite can die before it
# writes one, and that is exactly when the comment still needs to say something.
set -uo pipefail

AGG="${1:-}"
RUN_URL="${2:-}"

# The anchor CI greps for to decide between editing its previous comment and
# posting a new one. Keep it first and keep it stable.
echo '<!-- eval-report -->'
echo '### Behaviour evals'
echo

if [ -z "$AGG" ] || [ ! -s "$AGG" ]; then
  echo 'The suite wrote no aggregate — it failed before any case finished.'
  [ -n "$RUN_URL" ] && echo "The run log is the only record: $RUN_URL"
  exit 0
fi

if ! jq -e . "$AGG" >/dev/null 2>&1; then
  echo 'The suite'"'"'s aggregate could not be parsed, so there is nothing to summarise.'
  [ -n "$RUN_URL" ] && echo "The run log is the only record: $RUN_URL"
  exit 0
fi

jq -r '
  def pct: (. * 100 | round) / 100;

  "**\(.aggregates.casesPassed)/\(.aggregates.casesTotal) cases passed** · overall score \(.aggregates.overallScore | pct)"
    + (if .partial then " · ⚠️ partial run" else "" end),
  "",
  "| case | score | passed |",
  "|---|---|---|",
  (.cases[] | "| `\(.name)` | \(.aggregates.score | pct) | \(if .aggregates.passRate == 1 then "✅" else "❌" end) |")
' "$AGG"

# Only the graders that actually said no. On a green run this section is absent
# rather than empty — nobody needs a fold that opens onto nothing.
failed="$(jq -r '
  .cases[] as $c
  | $c.arms | to_entries[] as $arm
  | $arm.value[]
  | .graders[]
  | select(.passed == false)
  | "- `\($c.name)` · \($arm.key) arm · **\(.name)** — \(.explanation // "no explanation given")"
' "$AGG" 2>/dev/null | sort -u)"

if [ -n "$failed" ]; then
  echo
  echo '<details><summary>Graders that failed</summary>'
  echo
  echo "$failed"
  echo
  echo '</details>'
fi

echo
if [ -n "$RUN_URL" ]; then
  echo "[Full report]($RUN_URL) — the \`eval-report\` artifact carries the HTML, which"
  echo "shows each judge's votes and the excerpt it read."
fi
