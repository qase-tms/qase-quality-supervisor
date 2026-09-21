---
type: llm
---

The fixture has three distinct gaps: the Payments suite (id 4) holds no cases at all;
cases 11 and 12 are Manual, High priority and have never been executed; case 10 is
marked "to be automated" and has never run.

PASS if the response names at least two of those three gaps specifically — an empty
suite, the manual high-priority cases, or the never-executed case — rather than only
quoting an overall automation percentage.

FAIL if it names fewer than two of those gaps, if it reports only aggregate numbers
with no specific gap, or if it claims coverage is complete.
