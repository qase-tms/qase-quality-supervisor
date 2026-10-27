# Releasing

For maintainers. Users of the plugin need nothing here.

## Bump the version with the script, not by hand

The version appears in three places:

| File | Why it carries the version |
|------|----------------------------|
| `.claude-plugin/plugin.json` | The source of truth. |
| `.claude-plugin/marketplace.json` | What the marketplace offers. |
| `.codex-plugin/plugin.json` | The Codex manifest. |

It is repeated rather than interpolated because no manifest can read the
others.

So bump in one command:

```bash
scripts/set-version.sh 0.2.0
```

It rewrites all three, refuses a non-semver argument, and re-runs the consistency
check. It rewrites by pattern rather than by the current value, so it also repairs
a repository that has already drifted.

Then add the `CHANGELOG.md` entry and commit. The entry is not optional bookkeeping:
it becomes the release notes, and a tag for a version with no changelog section fails
the release workflow rather than publishing an empty one.

## Cutting the release

Once the version bump is merged to `main`, tag it and push:

```bash
git checkout main && git pull
git tag -a v0.4.0 -m "Quality Supervisor 0.4.0"
git push origin v0.4.0
```

`.github/workflows/release.yml` takes it from there: it asserts the tag matches the
version in the manifests, re-runs the version-sync check, extracts that version's
`CHANGELOG.md` section, and publishes the GitHub release. Tag format is `v<version>`,
annotated, message `Quality Supervisor <version>` — matching the tags already in the
repository.

Two things worth knowing:

- **The tag is the trigger and the decision.** Nothing decides *whether* to release;
  pushing the tag does. So push it only from a commit you intend to ship.
- **A mismatched tag fails rather than publishing.** Tagging `v0.4.0` at a tree whose
  manifests still say `0.3.0` would ship a plugin that disagrees with its own release.
  The workflow refuses instead. Fix with `scripts/set-version.sh`, commit, delete the bad
  tag (`git tag -d` and `git push origin :refs/tags/v0.4.0`), and re-tag.

`claude plugin tag` also exists and validates the same manifest agreement, but it
names tags `quality-supervisor--v<version>`. This repository uses the plain `v<version>`
form its earlier tags and releases already use.

## What guards the version

Two layers:

- **CI** — `.github/workflows/validate.yml` runs `verify-plugin.sh`, which calls
  `scripts/check-version-sync.sh` on every push and pull request. This is the gate.
- **A local pre-commit hook** — optional, for earlier feedback.

## Enabling the pre-commit hook

Opt-in, once per clone, because this repository has no install step that could
place it for you:

```bash
git config core.hooksPath .githooks
```

It runs only the version-sync check — a fraction of a second. It deliberately does
not run the full `verify-plugin.sh`, which installs the plugin through the
`claude` CLI and takes far too long for a commit.

Two limits worth knowing: it inspects the working tree rather than the index, so a
partial `git add` can still commit an inconsistent state, and `--no-verify`
bypasses it. CI catches both.

## Verifying a release

```bash
bash tests/test-version-sync.sh          # the version tooling itself
bash tests/test-release-notes.sh         # changelog extraction for the release
bash scripts/verify-plugin.sh --static-only  # manifests, secrets, guards, hook tests
bash scripts/verify-plugin.sh            # the above, plus a real install and inventory
```

`verify-plugin.sh` runs every `tests/test-*.sh`, so both test files are covered by the
first two commands and by CI.

The full run installs and uninstalls `quality-supervisor@quality-supervisor`
through the `claude` CLI and removes that marketplace registration on exit —
including one you added by hand. Expect to re-add it afterwards.
