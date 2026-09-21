---
type: llm
---

Three cases in the fixture failed repeatedly: cases 4 and 7 both passed and failed in the
window, while case 2 failed every run and never passed.

PASS if the response distinguishes the genuinely unstable cases from the one that is
consistently broken, and says which is which.

FAIL if it calls all of them flaky, calls all of them broken, names no specific case, or
answers only that they "keep failing" without separating the two populations.
