---
type: regex
target:
  source: file
  path: 'src/cart.test.ts'
pattern: '\[[\d,\s]*\b3\b[\d,\s]*\]'
match: not_contains
---
