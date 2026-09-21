---
type: llm
focus:
  source: file
  path: 'quality-pulse-DEMO-*.html'
---

This is a QA pulse card generated from a fixture whose window holds 214 results —
187 passed, 21 failed, 2 blocked, 4 skipped — a pass rate of 87.4%, 7 completed runs,
3 new cases, 4 new defects, and three active users.

PASS if the card is complete, self-contained HTML that names the project DEMO and the
window, and carries the fixture's real numbers — the pass rate, the result counts and
the run count must match the fixture rather than being invented or left as placeholders.

FAIL if any headline number contradicts the fixture, if template placeholders such as
"{{", "TODO" or "Lorem" survive in the output, if the project or window is missing, or
if the file is a fragment rather than a whole page.
