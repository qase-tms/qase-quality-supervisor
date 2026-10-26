# JavaScript / TypeScript

Syntax verified against reporter sources on 2026-10-26; where reporter docs disagree, this file wins.

## Contents

- Title-suffix rules shared by Jest, Playwright, Cypress, Mocha, Vitest, WDIO
- Jest, Playwright, Cypress, Cypress + Cucumber, Mocha, Vitest
- WDIO (mocha/jasmine), WDIO (cucumber), TestCafe, Newman, CucumberJS

## Title-suffix rules

`qase(...)` appends ` (Qase ID: 1,2)` to the test title; the reporter parses that suffix. A hand-written suffix works too. Keep the suffix last in the title and never wrap a title in `qase(...)` twice: only a trailing match is stripped. Gherkin tags take no spaces inside.

### Jest

**Detect:** `jest-qase-reporter`
**Import:** `const { qase } = require('jest-qase-reporter/jest')`
**Write:** `test(qase(1, 'name'), () => {})`
**Multi-ID:** `qase([1,2], 'name')`
**Also valid:** hand-written suffix `(Qase ID: 1,2)`; multi-project `qase.projects({P1:[1]}, 'name')`
**Never write:** import from `'jest-qase-reporter'` without `/jest`; a suffix with a different shape such as `(Qase ID:1)` or `(Qase ID: 1, 2)`
**Scope:** per test, title suffix. Jest's parser is stricter than the others: exactly one space after the colon and no space after commas, `(Qase ID: 1,2)`.

### Playwright

**Detect:** `playwright-qase-reporter`
**Import:** `import { qase } from 'playwright-qase-reporter'`
**Write:** `test(qase(1, 'name'), async () => {})`
**Multi-ID:** `qase([1,2], 'name')`
**Also valid:** `qase.id(1)` in the test body (deprecated); annotation `{ type: 'QaseID', description: '1' }`; multi-project `qase.projects({...})` in the body or `qase.projectsTitle(...)`
**Never write:** none known
**Scope:** per test. Keep the title form when the repo uses it; leave existing `qase.id(1)` calls alone rather than rewriting them.

### Cypress

**Detect:** `cypress-qase-reporter`
**Import:** `import { qase } from 'cypress-qase-reporter/mocha'`
**Write:** `it(qase(1, 'name'), () => {})`
**Multi-ID:** `qase([1,2], 'name')`
**Also valid:** multi-project `qase.projects({...}, 'name')`
**Never write:** import from `'cypress-qase-reporter'` or `'cypress-qase-reporter/cypress'`
**Scope:** per test, title suffix.

### Cypress + Cucumber

**Detect:** `cypress-qase-reporter` plus `@badeball/cypress-cucumber-preprocessor`
**Import:** none (Gherkin tag)
**Write:** `@QaseID(1)` on the line above the Scenario
**Multi-ID:** `@QaseID(1,2)`
**Also valid:** multi-project `@qaseid.PROJ1(1)`
**Never write:** none known
**Scope:** per scenario, tag with parentheses (not `=`); no spaces inside the tag.

### Mocha

**Detect:** `mocha-qase-reporter`
**Import:** `require('mocha-qase-reporter/mocha')`
**Write:** `it(qase(1, 'name'), () => {})`
**Multi-ID:** `qase([1,2], 'name')`
**Also valid:** multi-project `qase.projects(...)`
**Never write:** none known
**Scope:** per test, title suffix. Prefer the `/mocha` subpath for the import.

### Vitest

**Detect:** `vitest-qase-reporter`
**Import:** `import { addQaseId } from 'vitest-qase-reporter/vitest'`
**Write:** `test(addQaseId('name', [1]), () => {})`
**Multi-ID:** `addQaseId('name', [1,2])`
**Also valid:** multi-project `addQaseProjects('name', {P1:[1]})`
**Never write:** `qase(1, 'name')` (shown in the reporter docs, but the package exports no `qase`)
**Scope:** per test, title suffix. Note the argument order: name first, IDs second.

### WDIO (mocha/jasmine)

**Detect:** `wdio-qase-reporter`
**Import:** `import { qase } from 'wdio-qase-reporter'`
**Write:** `it(qase(1, 'name'), () => {})`
**Multi-ID:** `qase([1,2], 'name')`
**Also valid:** multi-project `qase.projects(...)`
**Never write:** import from a subpath of `wdio-qase-reporter` (it has none)
**Scope:** per test, title suffix.

### WDIO (cucumber)

**Detect:** `wdio-qase-reporter` with a cucumber framework
**Import:** none (Gherkin tag)
**Write:** `@QaseId=1`
**Multi-ID:** `@QaseId=1,2,3`
**Also valid:** none
**Never write:** none known
**Scope:** per scenario, tag. Multi-project is not documented; do not invent a form.

### TestCafe

**Detect:** `testcafe-reporter-qase`
**Import:** `import { qase } from 'testcafe-reporter-qase/qase'`
**Write:** `test.meta(qase.id(1).create())('name', async t => {})`
**Multi-ID:** `qase.id([1,2]).create()`
**Also valid:** multi-project `qase.projects({...}).create()`
**Never write:** `qase.id(1)` passed to `.meta()` without `.create()`
**Scope:** per test, via `.meta()`; `.create()` is mandatory.

### Newman

**Detect:** `newman-reporter-qase`
**Import:** none (comment in the collection's `exec` script lines)
**Write:** `// qase: 1` on the line before `pm.test`
**Multi-ID:** `// qase: 1, 2, 3`
**Also valid:** multi-project `// qase PROJ1: 1,2`
**Never write:** none known
**Scope:** comment inside the collection JSON. **Not verified — don't write:** relying on the comment binding per request rather than per `pm.test`. When a case reads as the whole request, propose it on each `pm.test` and say so in the step-8 row's Reason and chat summary; the Decision column settles it.

### CucumberJS

**Detect:** `cucumberjs-qase-reporter`
**Import:** none (Gherkin tag)
**Write:** `@QaseID=1`
**Multi-ID:** `@QaseID=1,2,3`
**Also valid:** legacy `@Q-1`, `@q1`, `@qaseid(1)`; multi-project `@qaseid.PROJ1(1)`
**Never write:** none known
**Scope:** per scenario, tag with `=` (Cypress + Cucumber uses parentheses).
