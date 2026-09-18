---
type: llm
---

The fixture contains four interesting cases. Case 4 (Checkout: apply promo code) and
case 7 (Search: filter by tag) both passed and failed in the window — they are flaky.
Case 2 (Login: SSO redirect) and case 9 (Export: CSV download) failed every single time
and never passed — they are broken, not flaky.

PASS if the response names cases 4 and 7 (by id or by title) as the unstable/flaky ones,
AND treats cases 2 and 9 as consistently failing rather than flaky — reporting them
separately, calling them broken or a regression, or routing them to failure triage.

FAIL if it calls case 2 or case 9 flaky, if it lists all four together without the
distinction, if it names no specific cases, or if it claims there is no flakiness.
