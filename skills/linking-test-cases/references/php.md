# PHP

Syntax verified against reporter sources on 2026-10-26; where reporter docs disagree, this file wins.

### PHPUnit

**Detect:** `qase/phpunit-reporter`
**Import:** `use Qase\PHPUnitReporter\Attributes\QaseId;`
**Write:** `#[QaseId(123)]` on the test method
**Multi-ID:** `#[QaseIds([1,2,3])]`
**Also valid:** none
**Never write:** none known
**Scope:** method only; PHP 8 attributes, not docblock annotations. No multi-project support.

### Pest

**Detect:** `qase/pest-reporter`
**Import:** `use function Qase\PestReporter\qase;`
**Write:** `qase()->caseId(123);` inside the test body
**Multi-ID:** `qase()->caseId(1, 2, 3)`
**Also valid:** none
**Never write:** `#[QaseId]` before `it(...)` (shown in the reporter docs, but the reader only reflects class methods)
**Scope:** runtime call, made when the test runs. No multi-project support.

### Codeception

**Detect:** `qase/codeception-reporter`
**Import:** `use Qase\Codeception\Attributes\QaseId;`
**Write:** `#[QaseId(123)]` on the test method
**Multi-ID:** `#[QaseIds([1,2,3])]`
**Also valid:** none
**Never write:** none known
**Scope:** method only, in Unit and Cest tests. **Not verified — don't write:** any form in Cept or Gherkin tests (no mechanism is known). No multi-project support.
