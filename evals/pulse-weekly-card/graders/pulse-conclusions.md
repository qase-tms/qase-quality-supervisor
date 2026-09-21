---
type: llm
---

The skill was asked for a QA pulse over a recent window of the DEMO project and writes a
self-contained HTML card. The fixture holds execution results, completed runs, new and
open defects, case authoring activity and a named set of users.

PASS if the response says it wrote the card AND reports concrete figures it got from
Qase — at minimum a pass rate or result counts, plus one of: a run count, the defect
backlog, or case authoring activity.

FAIL if it reports no figures at all, if it claims it could not produce the card, or if
it presents data it says was unavailable as though it had it.

Do not fail the response for figures that differ from any particular expected total: the
fixture is dated, so the window the skill picks shifts with the current date. Judge
whether it reported real figures and was honest about anything missing, not whether the
totals match a specific number.
