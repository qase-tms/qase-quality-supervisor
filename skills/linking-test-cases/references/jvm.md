# JVM (Java, Kotlin)

Syntax verified against reporter sources on 2026-10-26; where reporter docs disagree, this file wins.

### JUnit4

**Detect:** `io.qase:qase-junit4-reporter`
**Import:** `import io.qase.commons.annotation.QaseId;` (`QaseIds` for several)
**Write:** `@QaseId(123)` on the test method
**Multi-ID:** `@QaseIds({1,2})`
**Also valid:** none
**Never write:** none known
**Scope:** method only; a class-level annotation does not link. No multi-project support.

### JUnit5

**Detect:** `io.qase:qase-junit5-reporter`
**Import:** `import io.qase.commons.annotation.QaseId;` (`QaseIds` for several)
**Write:** `@QaseId(123)` on the test method
**Multi-ID:** `@QaseIds({1,2})`
**Also valid:** none
**Never write:** none known
**Scope:** method only. For `@ParameterizedTest`, one annotation covers all iterations. No multi-project support.

### TestNG

**Detect:** `io.qase:qase-testng-reporter`
**Import:** `import io.qase.commons.annotation.QaseId;` (`QaseIds` for several)
**Write:** `@QaseId(123)` on the test method
**Multi-ID:** `@QaseIds({1,2})`
**Also valid:** none
**Never write:** none known
**Scope:** method only. No multi-project support.

### Java Cucumber (v3-v7)

**Detect:** `io.qase:qase-cucumber-v3-reporter` through `io.qase:qase-cucumber-v7-reporter` (`qase-cucumber-vN-reporter`)
**Import:** none (Gherkin tag)
**Write:** `@QaseId=123`
**Multi-ID:** `@QaseIds=1,2`
**Also valid:** repeating the single tag, one ID each; `@QaseId=ABC-12` (links ID 12)
**Never write:** `@QaseId=1,2` (the comma form on the singular tag is silently dropped, even though the reporter docs show it)
**Scope:** per scenario, tag. No multi-project support.

### Kotlin JUnit4 / Android

**Detect:** `io.qase:qase-kotlin-junit4` or `io.qase:qase-kotlin-android`
**Import:** `import io.qase.commons.kotlin.junit4.*`
**Write:** `@QaseId(123L)` on the test function
**Multi-ID:** `@QaseIds(1L, 2L)`
**Also valid:** none
**Never write:** none known
**Scope:** function only. The test class needs `QaseRunner` registered or nothing reports. No multi-project support.

### Kaspresso

**Detect:** `io.qase:qase-kaspresso-reporter`
**Import:** `import io.qase.kaspresso.Qase`
**Write:** `Qase.id(123)` inside the test body
**Multi-ID:** `Qase.ids(1, 2)`
**Also valid:** none
**Never write:** none known
**Scope:** runtime call, made when the test runs. Needs `withQaseSupport()` in the Kaspresso setup. No multi-project support.
