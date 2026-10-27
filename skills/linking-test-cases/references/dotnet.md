# .NET

Syntax verified against reporter sources on 2026-10-26; where reporter docs disagree, this file wins.

NUnit, xUnit, xUnit v3 and MSTest share one attribute. There is no singular `QaseId` attribute; the plural `QaseIds` takes one ID too. For `[TestCase]`, `[Theory]` and `[DataRow]`, one attribute covers all iterations. No multi-project support.

### NUnit

**Detect:** `Qase.NUnit.Reporter`
**Import:** `using Qase.Csharp.Commons.Attributes;`
**Write:** `[QaseIds(123)]` on the test method
**Multi-ID:** `[QaseIds(1, 2, 3)]`
**Also valid:** none
**Never write:** `[QaseId(123)]` (no such attribute)
**Scope:** method only.

### xUnit

**Detect:** `Qase.XUnit.Reporter`
**Import:** `using Qase.Csharp.Commons.Attributes;`
**Write:** `[QaseIds(123)]` on the test method
**Multi-ID:** `[QaseIds(1, 2, 3)]`
**Also valid:** none
**Never write:** `[QaseId(123)]` (no such attribute)
**Scope:** method only.

### xUnit v3

**Detect:** `Qase.XUnit.V3.Reporter`
**Import:** `using Qase.Csharp.Commons.Attributes;`
**Write:** `[QaseIds(123)]` on the test method
**Multi-ID:** `[QaseIds(1, 2, 3)]`
**Also valid:** none
**Never write:** `[QaseId(123)]` (no such attribute)
**Scope:** method only.

### MSTest

**Detect:** `Qase.MSTest.Reporter`
**Import:** `using Qase.Csharp.Commons.Attributes;`
**Write:** `[QaseIds(123)]` on the test method
**Multi-ID:** `[QaseIds(1, 2, 3)]`
**Also valid:** none
**Never write:** `[QaseId(123)]` (no such attribute)
**Scope:** method only.

### Reqnroll

**Detect:** `Qase.Reqnroll.Reporter`
**Import:** none (Gherkin tag)
**Write:** `@QaseId:123`
**Multi-ID:** `@QaseId:1,2` as a single tag
**Also valid:** a feature-level `@QaseId:` tag, which applies to its scenarios
**Never write:** several `@QaseId:` tags expecting them to merge
**Scope:** per scenario or feature. With more than one `@QaseId:` tag (including feature plus scenario) the last one wins; they are not merged, so list every ID in one tag.
