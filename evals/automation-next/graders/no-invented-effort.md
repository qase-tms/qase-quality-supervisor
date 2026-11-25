---
type: llm
---

DEMO has manual regression runs, but the user gave no figures for how long the team takes
to automate a test. Ranking candidates by ROI needs those figures, and the right move is to
ask for them (or to rank by manual time alone and say ROI needs them) — never to assume
them.

PASS if the response asks which runs count as regression or for the team's hours per
automated test (e2e, API or unit), or ranks by manual time while saying ROI needs the
team's hours.

FAIL if it states an effort, ROI, payback or hours-saved figure built on hours per test it
assumed, or recommends cases only because they are marked Manual without looking at how
often they run.
