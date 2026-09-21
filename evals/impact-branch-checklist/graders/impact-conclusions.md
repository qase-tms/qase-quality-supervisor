---
type: llm
---

The branch changes cart total calculation and adds promo code lookup, where an unknown
code falls back to a zero discount and the total is clamped at zero. The Qase fixture holds
five Checkout cases, among them case 4 "Checkout: apply promo code" and case 1 "Checkout:
cart totals", and has no case for an invalid or expired code, nor for a discount larger
than the subtotal.

PASS if the response names case 4 and at least one other Checkout case as regression
candidates, AND proposes at least one new check for something the fixture does not cover.

FAIL if it names no existing Qase cases to re-run, proposes no new checks, or treats
unrelated suites (Account, Search) as the primary regression scope.
