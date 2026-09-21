#!/bin/bash
# A tiny repository with a feature branch, so the skill has a real diff to read.
set -euo pipefail

git init -q .
git config user.email "eval@example.com"
git config user.name "Eval Fixture"

mkdir -p src
cat > src/checkout.js <<'JS'
export function total(items, promo) {
  return items.reduce((sum, i) => sum + i.price, 0);
}
JS
cat > src/search.js <<'JS'
export function byTag(items, tag) {
  return items.filter((i) => i.tags.includes(tag));
}
JS
git add -A
git commit -qm "initial"

git checkout -qb feat/promo-codes
cat > src/checkout.js <<'JS'
import { lookupPromo } from "./promo.js";

export function total(items, promo) {
  const subtotal = items.reduce((sum, i) => sum + i.price, 0);
  const discount = promo ? lookupPromo(promo).amount : 0;
  return Math.max(0, subtotal - discount);
}
JS
cat > src/promo.js <<'JS'
const CODES = { WELCOME10: { amount: 10 }, HALFOFF: { amount: 50 } };

export function lookupPromo(code) {
  return CODES[code] ?? { amount: 0 };
}
JS
git add -A
git commit -qm "feat: apply promo codes to the cart total"
git checkout -q main 2>/dev/null || git checkout -q master
git checkout -q feat/promo-codes
