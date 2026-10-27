# Go

Syntax verified against reporter sources on 2026-10-26; where reporter docs disagree, this file wins.

### Go

**Detect:** `github.com/qase-tms/qase-go/pkg/qase-go` in go.mod
**Import:** `"github.com/qase-tms/qase-go/pkg/qase-go/qase"`
**Write:** add `QaseIDs: []int64{101}` to the metadata of an existing `qase.Test(t, qase.TestMetadata{…}, …)` call — never wrap a test that lacks one
**Multi-ID:** `QaseIDs: []int64{1, 2}`
**Also valid:** none
**Never write:** none known
**Scope:** per test, through the `qase.Test` wrapper. A plain test without `qase.Test` is report only: its result is sent with no case link. The package needs a `TestMain` for the reporter to run. No multi-project support.
