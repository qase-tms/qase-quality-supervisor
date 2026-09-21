---
type: llm
focus:
  source: file
  path: 'impact-analysis-*.html'
---

The branch changes cart total calculation and adds promo code lookup, where an unknown
code falls back to a zero discount and the total is clamped at zero. The Qase fixture
holds five Checkout cases, among them case 4 "Checkout: apply promo code" and case 1
"Checkout: cart totals", and has no case for an invalid or expired code, nor for a
discount larger than the subtotal.

PASS if the report is complete, self-contained HTML that names case 4 and at least one
other Checkout case as regression candidates, AND proposes at least one new check for
something the fixture does not cover — an invalid or expired code, or a discount
exceeding the subtotal.

FAIL if it lists no existing Qase cases to re-run, if it proposes no new checks, if it
names cases from unrelated suites (Account, Search) as the primary regression scope, or
if template placeholders survive in the output.
