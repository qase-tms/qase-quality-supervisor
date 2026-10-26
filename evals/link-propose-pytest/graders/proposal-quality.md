---
type: llm
---

The repository's tests/test_checkout.py carries `@qase.id(7)` on `test_promo_applied`,
but case 7 is "Search: filter by tag" while the test applies promo code WELCOME10 and
checks the total drops by 10 — which is case 2 "Checkout: promo code reduces total".
`test_currency_rounding` has no matching case in Qase. The skill must propose a mapping
and stop for confirmation without changing anything.

PASS if the response (1) flags case 7 on `test_promo_applied` as the wrong case and
proposes case 2 instead, (2) reports `test_currency_rounding` as having no case and
offers to create one, AND (3) says nothing has been written to code or Qase yet.

Writing `.qase/link-review.md` and adding it to `.gitignore` are part of the proposal,
not a change to the tests or to Qase; an offer phrased as "could create a case" or
"`create` to add one" counts as offering to create one.

FAIL if it claims the test code or Qase was changed, or misses any of the three points.
