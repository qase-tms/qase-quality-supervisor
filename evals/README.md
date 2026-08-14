# Eval harness

Three test layers for the Quality Supervisor skills. **Local only** — none of
this runs in CI, because the agent layers need an authenticated Claude session
that GitHub runners don't have. `scripts/verify-plugin.sh` remains the only CI
gate.

```bash
export QASE_API_TOKEN=...        # required by layers 1 and 3

./evals/run.sh layer1            # query correctness      — seconds
./evals/run.sh layer2            # skill triggering       — ~15 min
./evals/run.sh layer3            # end-to-end scenarios   — minutes, needs fixtures
./evals/run.sh all
```

The target project defaults to `DEVX`; override with `QS_EVAL_PROJECT`.

Any layer exits non-zero if a case failed.

## Layer 1 — query correctness

Runs every QQL query and REST call the skills tell the model to make, against a
live project, and asserts the API accepted it. Seconds to run, and it is the
check that would have caught the skills' original drafts: their field names were
plausible but wrong, and a wrong name is a hard error rather than an empty
result.

Six rows assert the **opposite** — that known-invalid forms still fail
(`priority = "critical"`, `suite = <id>`, `created` on a run or result,
`SELECT` after the conditions). If one of those starts passing, `references/qql.md`
has gone stale and needs re-verifying rather than trusting.

**A failure here means** a query in a skill no longer works, or the API changed.
Fix the skill, then update the reference.

A row marked `ok_nonzero` that returns zero is usually data drift in the target
project rather than a broken query — relax that row to `ok` if the data it
depended on is gone.

## Layer 2 — skill triggering

For each prompt, runs a headless session with the plugin loaded and the Qase MCP
tools blocked, then reads the trace for which skill fired. Blocking the tools
keeps a case to ~40 seconds: only the routing decision matters here.

```bash
QS_EVAL_FILTER="flake rate" ./evals/run.sh layer2   # one case, by substring
QS_EVAL_RUNS=3 ./evals/run.sh layer2                # repeat each case
```

**Routing is not deterministic, and the variance is larger than it looks.** The
same prompt routes differently across runs, so a single failure is not proof of a
regression. Worse, `QS_EVAL_RUNS=3` is not enough to settle it: a case measured at
1/3 in one pass measured 3/3 within the hour, unchanged. Treat a three-run figure
as a smoke test, not a metric — use 5–10 runs for a number you intend to quote,
and don't run anything else agentic at the same time (concurrent sessions have
visibly skewed a pass).

What *is* stable across every measurement so far, and worth watching for
regressions, is the qualitative part: no case has ever routed to the wrong skill,
and no near-miss has ever triggered one. Those two properties are the ones that
would damage a user — a wrong route inverts the advice, and over-triggering
hijacks unrelated questions. Recall (did the right skill fire at all) is the noisy
part.

Three outcomes to read differently:

- **FAIL, fired the wrong skill of ours** — a description is too broad, or two
  overlap. This is the dangerous one: `triaging-test-failures` and `analyzing-test-flakiness`
  prescribe opposite actions, so confusing them inverts the advice.
- **FAIL, fired nothing** — a description is too narrow for that phrasing.
- **WARN, another plugin fired** — a skill from a different installed plugin won
  the routing. That is a property of the developer's environment, not of these
  descriptions, so it is reported separately and does not count as a failure.
  Observed in practice: an aggressive `using-superpowers` description claiming
  "use when starting any conversation" takes prompts that carry no
  test-management vocabulary.

That last point has a corollary worth knowing: **a plugin cannot reasonably claim
domain-neutral phrasing.** "What's blocking the release?" could be about a pull
request, a deployment, or a ticket; a Qase plugin that hijacked it in a non-Qase
project would be over-triggering. Prompts that route reliably are the ones
carrying test-management vocabulary — flaky, coverage, triage, suites, go/no-go.

Cases like that carry `kind: domain-neutral`. They stay in the suite because the
behaviour is worth watching, but they should not be read as recall failures — the
right skill firing is a bonus, not a requirement. Measured over 12 runs, that one
lands about 40% of the time and has been drifting down; adding "in Qase" to the
same question makes it route. Widening a description to catch it would buy that
40% at the cost of hijacking unrelated questions, which is the worse trade.

`MCP tools were not blocked` means the tool names in `--disallowedTools` no
longer match the server's; fix them before running a full pass, or every case
does real API work.

Each run happens in an empty temp directory, deliberately. With the plugin repo
as the working directory the agent can Grep and Read the `SKILL.md` files and
answer from them — which inflates the score, since a real user's project does
not contain the plugin's source.

## Layer 3 — end-to-end scenarios

Runs realistic prompts with MCP **enabled** against seeded fixtures, and asserts
that specific claims appear in the report and specific wrong claims do not.

```bash
./evals/fixtures/seed.sh         # create the fixtures, print their IDs
./evals/run.sh layer3
./evals/fixtures/teardown.sh     # ALWAYS do this afterwards
```

**This writes to a real project.** Every fixture is titled `[QS-TEST] …` and
lives in its own suite, and `seed.sh` is idempotent, but they are visible to
whoever else uses that project while they exist. Tear them down when you finish
rather than leaving them.

The fixtures centre on one pair, which is the whole point of the layer:

| Fixture | History | Must be reported as |
|---|---|---|
| `[QS-TEST] flaky-case` | pass, fail, pass, fail | flaky |
| `[QS-TEST] broken-case` | fail, fail, fail | a regression, **not** flaky |

A failure here is the most informative result in the harness: it means a skill's
*methodology* did not conclude what the rewrite intended, not merely that a query
was malformed — **provided the assertion is sound.** Substring matching against
free prose is easy to get wrong, and the first version of these cases failed twice
on correct behaviour:

- A report that correctly listed the broken case under "not flaky, consistently
  failing" tripped a `must_not_contain` on that case's ID. Absence checks over the
  whole text can't express "must not be called flaky" — so the cases ask targeted
  questions with a YES/NO opening instead of listing everything.
- A skill answered "это регрессия, а не флаки" — exactly right, in the session's
  configured language — and failed on `missing:'regression'`. The runner now pins
  the answer language to English.

When a Layer 3 case fails, read the excerpt before believing it: check the skill
was wrong rather than the assertion.

Two things about the environment:

- **Fixtures are written over REST but read through QQL, whose index lags.**
  Straight after seeding they are invisible to a skill. The runner checks for
  this and says so rather than blaming the skill — wait and re-run.
- **The shipped `.mcp.json` points at the hosted OAuth endpoint, which a headless
  session cannot authenticate against.** So the runner starts its own local
  token-based server via `--mcp-config`, named `qase` so the plugin's
  destructive-call guard hook still applies. The token goes to a temp file with
  owner-only permissions outside the repo and is removed on exit.

`teardown.sh` calls DELETE endpoints directly over REST. That is deliberate and
is not a hole in the guard: the hook blocks the *model* from deleting Qase data,
which Layer 3 exercises for real, while the teardown script is maintenance run by
a human.

## Adding cases

The case files are TSV — tab-separated, one case per row, header first — so bash
reads them without a parser dependency.

| File | Columns |
|---|---|
| `layer1-queries/queries.tsv` | `kind` (`qql`\|`rest`), `expect` (`ok`\|`ok_nonzero`\|`error`), `label`, query or path |
| `layer2-triggering/cases.tsv` | `kind` (`direct`\|`paraphrase`\|`near-miss`\|`domain-neutral`), `expected` (skill name or `none`), `prompt` |
| `layer3-scenarios/cases.tsv` | `label`, `prompt`, `must_contain`, `must_not_contain` (both `\|`-separated; `FLAKY_ID`, `BROKEN_ID`, `DEFECT_ID` are substituted from `state.json`) |

Keep near-miss rows in Layer 2 as you add positive ones. Over-triggering is
harder to notice than under-triggering and does more damage.

## Longer term

`claude plugin eval` is the built-in harness for exactly this — `evals/**/case.yaml`
plus `graders/*.md`, with `--ablation with-without` to measure the plugin's
contribution against a no-plugin baseline, `--runs` for nondeterminism, and
`--threshold` for a gate. It is behind early access and does nothing on an
account without it. When that opens, Layers 2 and 3 should move onto it; the case
files here are deliberately one-row-per-case to make that a translation rather
than a rewrite.
