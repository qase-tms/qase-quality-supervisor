# Python

Syntax verified against reporter sources on 2026-10-26; where reporter docs disagree, this file wins.

### pytest

**Detect:** `qase-pytest`
**Import:** `from qase.pytest import qase`
**Write:** `@qase.id(1)` above the test function
**Multi-ID:** `@qase.id([1,2])`
**Also valid:** multi-project `@qase.project_id("PROJ1", [1,2])`
**Never write:** none known
**Scope:** per test function, decorator. For `parametrize`, one marker per test function covers every iteration. **Not verified — don't write:** class-level decorators (inheritance is unconfirmed) and per-parameter `pytest.param(..., marks=qase.id(5))`.

### pytest-bdd

**Detect:** `qase-pytest` together with `pytest-bdd`
**Import:** none (Gherkin tag)
**Write:** `@qase.id=1`
**Multi-ID:** `@qase.id=1,2`
**Also valid:** multi-project `@qase.project_id.PROJ1=1,2`
**Never write:** none known
**Scope:** per scenario, tag with `=` (Behave uses `:`). No spaces inside the tag.

### Robot Framework

**Detect:** `qase-robotframework`
**Import:** none (tag)
**Write:** `[Tags]    Q-1`
**Multi-ID:** one tag per ID, `[Tags]    Q-1    Q-2`
**Also valid:** multi-project `Q-PROJECT.PROJ1-1,2`
**Never write:** none known
**Scope:** per test case, tags. The run must pass `--listener` for the reporter to report at all.

### Behave

**Detect:** `qase-behave`
**Import:** none (Gherkin tag)
**Write:** `@qase.id:1`
**Multi-ID:** `@qase.id:1,2`
**Also valid:** multi-project `@qase.project_id.PROJ1:1,2`
**Never write:** none known
**Scope:** per scenario, tag with `:` (pytest-bdd uses `=`). **Not verified — don't write:** the tag on a Feature line (feature tags are not confirmed to be read). The run needs the `-f` formatter to report.

### Tavern

**Detect:** `qase-tavern`
**Import:** none (inside `test_name`)
**Write:** `test_name: QaseID=1 Title`
**Multi-ID:** `QaseID=1,2,3`
**Also valid:** multi-project `QaseProjectID.PROJ1=1`
**Never write:** `QaseID` together with `QaseProjectID` in one name (`QaseID` is then ignored)
**Scope:** per test, inside the `test_name` string.
