#!/bin/bash
# A mixed repo (Vitest, Java Cucumber, plain pytest without qase-pytest) whose review
# file the user has already filled in, with the traps step 9 must not fall into: an
# already-linked row, a rejected row, an unknown case ID and a missing reporter.
set -euo pipefail

git init -q .
git config user.email "eval@example.com"
git config user.name "Eval Fixture"

cat > package.json <<'JSON'
{
  "name": "demo-shop",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "vitest run"
  },
  "devDependencies": {
    "vitest": "^3.2.0",
    "vitest-qase-reporter": "^1.1.0"
  }
}
JSON

mkdir -p src features legacy .qase
cat > src/cart.ts <<'TS'
export type Item = { name: string; price: number };

export function total(items: Item[]): number {
  const cents = items.reduce((sum, i) => sum + Math.round(i.price * 100), 0);
  return cents / 100;
}
TS

cat > src/cart.test.ts <<'TS'
import { expect, test } from 'vitest';
import { addQaseId } from 'vitest-qase-reporter/vitest';
import { total } from './cart';

test('cart total', () => {
  expect(total([{ name: 'book', price: 12 }, { name: 'pen', price: 3 }])).toBe(15);
});

test(addQaseId('empty cart', [4]), () => {
  expect(total([])).toBe(0);
});

test('currency rounding', () => {
  expect(total([{ name: 'gum', price: 0.125 }, { name: 'mint', price: 0.2 }])).toBe(0.33);
});
TS

cat > pom.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>io.example</groupId>
  <artifactId>demo-shop-bdd</artifactId>
  <version>0.1.0</version>
  <dependencies>
    <dependency>
      <groupId>io.cucumber</groupId>
      <artifactId>cucumber-java</artifactId>
      <version>7.20.1</version>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>io.qase</groupId>
      <artifactId>qase-cucumber-v7-reporter</artifactId>
      <version>4.1.0</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
XML

cat > features/promo.feature <<'FEATURE'
Feature: Promo codes

  Scenario: Promo codes
    Given a cart holding items worth 30.00
    When I apply the promo code "WELCOME10"
    Then the total is 20.00
    When I replace it with the promo code "BOGUS"
    Then the total is 30.00
FEATURE

cat > legacy/requirements.txt <<'TXT'
pytest>=8
TXT
cat > legacy/test_search.py <<'PY'
from search import by_tag


def test_filter_by_tag():
    items = [{"name": "hat", "tags": ["sale"]}, {"name": "scarf", "tags": []}]
    assert [i["name"] for i in by_tag(items, "sale")] == ["hat"]
PY
cat > legacy/search.py <<'PY'
def by_tag(items, tag):
    return [i for i in items if tag in i["tags"]]
PY

cat > .gitignore <<'TXT'
node_modules/
.qase/link-review.md
.qase/links.json
TXT

cat > .qase/links.json <<'JSON'
{"version": 1, "project": "DEMO", "storage": "local", "entries": []}
JSON

cat > .qase/link-review.md <<'MD'
# Qase link review — DEMO

Fill the Decision column: `accept`, `reject`, `edit: <id>[,<id>…]`, `create`, `skip`,
or leave it empty (undecided). Then reply `done` in chat.

## New links

| # | Test | Case(s) | Confidence | Reason | Decision |
|---|---|---|---|---|---|
| 1 | src/cart.test.ts:5 cart total | 1 Checkout: cart totals | high | Adds two items and asserts the total is their sum, as the steps do | accept |
| 2 | features/promo.feature:3 Promo codes | 2 Checkout: promo code reduces total; 3 Checkout: unknown promo code is ignored | medium | Applies WELCOME10 and then BOGUS; one scenario walks both cases | accept |
| 5 | legacy/test_search.py:4 test_filter_by_tag | 7 Search: filter by tag | high | Filters by the tag "sale" and asserts only tagged items remain | accept |
| 6 | src/cart.test.ts:5 cart total | 3 Checkout: unknown promo code is ignored | low | Only the Checkout suite overlaps; the test applies no promo code | reject |

## Existing IDs

| # | Test | Case(s) | Confidence | Reason | Decision |
|---|---|---|---|---|---|
| 3 | src/cart.test.ts:9 empty cart | 4 Checkout: empty cart total is zero | high | Confirmed; the case is still Manual, so its update can be offered | accept |

## Tests without a case

| # | Test | Case(s) | Confidence | Reason | Decision |
|---|---|---|---|---|---|
| 4 | src/cart.test.ts:13 currency rounding | — | — | No case covers currency rounding; `create` to add one | edit: 999 |

## Cases with no test

| # | Test | Case(s) | Confidence | Reason | Decision |
|---|---|---|---|---|---|

## Qase update

Decision: later
MD

git add -A
git commit -qm "initial"
