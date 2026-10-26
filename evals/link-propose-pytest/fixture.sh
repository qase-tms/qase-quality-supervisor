#!/bin/bash
# A pytest repo with qase-pytest installed: one correct ID, one wrong ID, two unlinked
# tests with an obvious case each, and one test no case covers.
set -euo pipefail

git init -q .
git config user.email "eval@example.com"
git config user.name "Eval Fixture"

cat > pyproject.toml <<'TOML'
[project]
name = "demo-shop"
version = "0.1.0"
requires-python = ">=3.10"

[project.optional-dependencies]
dev = ["pytest>=8", "qase-pytest>=6"]
TOML

mkdir -p shop tests
: > shop/__init__.py
cat > shop/cart.py <<'PY'
from decimal import Decimal, ROUND_HALF_UP

PROMOS = {"WELCOME10": Decimal("10")}


class Cart:
    def __init__(self):
        self.items = []
        self.promo = None

    def add(self, name, price):
        self.items.append((name, Decimal(str(price))))

    def apply_promo(self, code):
        if code in PROMOS:
            self.promo = code

    def total(self):
        subtotal = sum((price for _, price in self.items), Decimal("0"))
        discount = PROMOS.get(self.promo, Decimal("0"))
        return max(Decimal("0"), subtotal - discount).quantize(Decimal("0.01"), ROUND_HALF_UP)
PY

cat > tests/test_checkout.py <<'PY'
from decimal import Decimal

from qase.pytest import qase

from shop.cart import Cart


@qase.id(1)
def test_cart_total():
    cart = Cart()
    cart.add("book", 12)
    cart.add("pen", 3)
    assert cart.total() == Decimal("15.00")


@qase.id(7)
def test_promo_applied():
    cart = Cart()
    cart.add("book", 30)
    cart.apply_promo("WELCOME10")
    assert cart.total() == Decimal("20.00")


def test_unknown_promo():
    cart = Cart()
    cart.add("book", 30)
    cart.apply_promo("BOGUS")
    assert cart.total() == Decimal("30.00")


def test_empty_cart():
    assert Cart().total() == Decimal("0.00")


def test_currency_rounding():
    cart = Cart()
    cart.add("gum", "0.005")
    assert cart.total() == Decimal("0.01")
PY

git add -A
git commit -qm "initial"
