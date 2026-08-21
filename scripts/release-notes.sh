#!/bin/bash
#
# Prints the CHANGELOG.md section for one version, for use as GitHub release notes.
#
# The changelog is written by hand and says why each change was made, so it is a far
# better release note than a generated commit list. This script is the seam between
# the two: the release workflow calls it, and tests/test-release-notes.sh exercises it
# against fixtures.
#
# Exits non-zero when the version has no section, so a tag pushed for a version that
# was never written up fails the release instead of publishing empty notes.
#
# Usage: release-notes.sh <version> [changelog-path]
#   e.g. release-notes.sh 0.3.0

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <version> [changelog-path]" >&2
  exit 1
fi

VERSION="$1"
CHANGELOG="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/CHANGELOG.md}"

if [ ! -f "$CHANGELOG" ]; then
  echo "FAIL: no changelog at $CHANGELOG." >&2
  exit 1
fi

# Sections look like `## [0.3.0] - 2026-08-20`. Print from the requested version's
# heading up to (not including) the next `## [` heading. The version is matched
# literally — awk's index() rather than a regex — so dots in "0.1.1" cannot match
# "0111" and a caller cannot inject a pattern.
notes="$(awk -v want="## [${VERSION}]" '
  index($0, want) == 1 { inside = 1; next }
  inside && /^## \[/    { exit }
  inside                { print }
' "$CHANGELOG")"

# Trim leading and trailing blank lines, keeping the interior intact.
notes="$(printf '%s\n' "$notes" | awk 'NF {found = 1} found {print}' | awk '
  { lines[NR] = $0; if (NF) last = NR }
  END { for (i = 1; i <= last; i++) print lines[i] }
')"

if [ -z "$notes" ]; then
  echo "FAIL: CHANGELOG.md has no section for version ${VERSION} (expected a '## [${VERSION}]' heading with content)." >&2
  exit 1
fi

printf '%s\n' "$notes"
