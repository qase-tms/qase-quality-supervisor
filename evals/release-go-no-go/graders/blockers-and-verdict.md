---
type: llm
---

The fixture holds one blocker defect (301, promo code not applied) and one critical
defect (302, CSV export), three failing cases, and two cases with no result against the
milestone at all.

PASS if the response gives a clear verdict on shipping (no-go, or go with named
conditions) AND names the blocker defect 301 as a reason, AND mentions the untested
gap — that some cases have no result against this milestone.

FAIL if it gives no verdict, if it recommends shipping without naming the blocker, or
if it reports only a pass rate with no blocking items.
