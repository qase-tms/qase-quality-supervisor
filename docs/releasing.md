# Releasing

For maintainers. Users of the plugin need nothing here.

## Bump the version with the script, not by hand

The version appears in four places:

| File | Why it carries the version |
|------|----------------------------|
| `.claude-plugin/plugin.json` | The source of truth. |
| `.claude-plugin/marketplace.json` | What the marketplace offers. |
| `.mcp.json` | The `X-Qase-Integration` marker, reported to Qase analytics. |
| `README.md` | The `QASE_MCP_INTEGRATION` value in the self-run example. |

It is repeated rather than interpolated because `.mcp.json` has no way to
interpolate it: Claude Code expands environment variables and
`${CLAUDE_PLUGIN_ROOT}` there, but exposes no plugin-version variable. An
unexpanded placeholder would not fail loudly either — the MCP server validates the
marker's version and silently drops a malformed one while keeping the name, so the
call would still be counted, just without a version.

So bump in one command:

```bash
scripts/set-version.sh 0.2.0
```

It rewrites all four, refuses a non-semver argument, and re-runs the consistency
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
  manifests still say `0.3.0` would ship a plugin that disagrees with its own release,
  and its integration marker would report the stale version into Qase analytics. The
  workflow refuses instead. Fix with `scripts/set-version.sh`, commit, delete the bad
  tag (`git tag -d` and `git push origin :refs/tags/v0.4.0`), and re-tag.

`claude plugin tag` also exists and validates the same manifest agreement, but it
names tags `quality-supervisor--v<version>`. This repository uses the plain `v<version>`
form its earlier tags and releases already use.

## Why a stale version is worse than a broken one

A wrong-but-well-formed version passes the MCP server's validation exactly as
well as a correct one. Nothing errors, nothing is dropped: the calls keep being
attributed to this plugin, filed under a version nobody is running. That is the
failure this tooling exists to prevent — it is invisible in every log and only
shows up as a confusing analytics chart weeks later.

Two layers guard it:

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

Attribution itself cannot be verified from this repository: it needs an
authenticated call from an installed plugin, then a look at the `PUBLIC_API_CALL`
event, where `mcp_integration_name` should read `quality-supervisor` alongside an
unchanged `source_name` (`qase-mcp-hosted`) and `mcp_client_name` (the AI host).
