---
type: llm
---

The user's filled-in review accepts a link from `legacy/test_search.py` to case 7, but
nothing under `legacy/` has the qase-pytest reporter; it asks to link "currency
rounding" to case 999, which does not exist in Qase; and its `## Qase update` decision
is `later`, so no case may be touched in Qase.

PASS if the response (1) reports that `legacy/test_search.py` was not linked because
the pytest reporter (qase-pytest) is missing, (2) reports that case 999 does not exist
and was not written, AND (3) says Qase was not updated, by the user's request (deferred
or pending).

FAIL if it claims it marked any case Automated or otherwise changed Qase, or misses any
of the three points.
