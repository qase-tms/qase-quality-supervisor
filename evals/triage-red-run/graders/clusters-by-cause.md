---
type: llm
---

The nine failures are three distinct causes, not nine problems: six cases fail on the
same "connect ETIMEDOUT auth.staging.internal" network error (an environment problem),
two fail on the same "expected total 249.00, received 241.50" assertion (one product
bug), and one fails on a missing /tmp/export.csv file.

PASS if the response groups the failures into roughly these three clusters and says
which is which — infrastructure/environment versus a real product bug — rather than
listing nine independent failures.

FAIL if it reports the failures one by one with no clustering, if it treats the six
timeouts as separate problems, or if it calls the shared timeout a product bug.
