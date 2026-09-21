# Behaviour evals

`claude plugin eval` checks what the rest of CI cannot: that a natural request
reaches the right skill and that the skill finishes the job. Manifest and install
checks live in `scripts/verify-plugin.sh`; this is the other half.

## Running them

The command needs Claude Code 2.1.269 or later. The stable channel is behind, so
install one beside your own CLI and point the runner at it:

    npm install --prefix /tmp/eval-cli @anthropic-ai/claude-code@2.1.276
    export CLAUDE_EVAL_BIN=/tmp/eval-cli/node_modules/.bin/claude

    bash scripts/run-evals.sh --smoke          # what CI runs on every PR
    bash scripts/run-evals.sh                  # both arms, three runs, the HTML cases
    bash scripts/run-evals.sh --case 'triage-*'

Every run writes `evals/results/<timestamp>/report.html`. Open it before drawing
any conclusion from a red case: it carries each grader's verdict, and for judged
graders the votes and the excerpt they saw.

## How a case is built

    evals/<case>/
      prompt.md            # what the user types, plus turn and tool limits
      case.yaml            # only when the case needs a scaffold script
      mocks/qase/          # this case's fixture
      graders/*.md         # one check per file

Qase never runs for real. Predictable tools answer from static files under
`evals/mocks/qase/`; `qql_search` answers from an agent mock, because a static
file returns one answer per tool while a skill issues an aggregate, a candidate
query and a per-case history in turn, whose response shapes differ.

An agent mock answers through a model, so after a clean run its answers are copied
out of `evals/results/<ts>/mock-recordings/` and committed. `ADOPT.txt` beside the
recordings says what goes where — for a per-case mock that is
`evals/<case>/mocks/.replay/qase/`, beside the mock that produced them.

A recording answers a call whose query matches it *textually*. The model under test
rephrases its QQL slightly from run to run, so recordings cover the repeated queries
and the rest still reach the mock's model: measured on the pilot case, 7 of 11 calls
replayed and 4 did not. Replay removes the cost and the variance from the repeated
part; it does not make a run fully reproducible, and CI needs the API key either way.

All fixtures are synthetic, against an invented project `DEMO`. Real Qase
responses carry colleagues' email addresses and attachment links, and this
repository is public.

A grader file is frontmatter only — a comment placed before the frontmatter makes
the harness reject the case with `graders: Required`. Anything you want to explain
about a grader goes in the rubric body of an `llm` grader, or in this document.

## Three traps, each of which cost us a debugging session

**A mock that aborts measures nothing.** When a mock rejects a call, the run scores
zero and the grader list comes back empty — so the plugin could have behaved
perfectly and you would not know. Keep `expect:` as loose as the fixture allows
(`query: string`) and keep `abort_when:` an outright prohibition, telling the mock to
answer `{"total":0,"entities":[]}` for anything it cannot answer. We lost two cases to
an `expect:` regex on the project name, which fired on the legitimate query
`entity = "result" and run_id = 1`, and to an `abort_when:` that let the mock judge
QQL validity — it rejected the aggregate syntax Qase actually supports.

**`mock_calls` reaches a grader as JSON, with the quotes escaped.** A pattern for
`project = "DEMO"` finds nothing; the text contains `project = \"DEMO\"`. Write
`project\s*=\s*\\?"DEMO` and the pattern matches either form.

**Whatever the fixture leaves unsaid, the mock model will invent.** Ours said nothing
about the `is_flaky` flag or about case update dates, so the mock flagged a case that
had never passed as flaky, and reported cases touched nine days earlier as six months
stale — and the adoption pass pinned both answers. Before recording, read the skill and
list what it will ask for; state each answer in the fixture, including the ones that are
"obviously" nothing.

## Adding a case

1. `claude plugin eval init --bare <name>` for the blank skeleton, or copy the
   nearest existing case.
2. Write the prompt the way a user would type it — don't name the skill.
3. Give it a `skill-fired` grader, at least one `min: 0, max: 0, arm: both`
   grader for the skill that must *not* fire, and one `llm` grader for the answer.
   Without `arm: both` a negative grader is dropped from both arms and asserts
   nothing.
4. Build the fixture so that one specific wrong answer is visible — an empty
   suite, failures that are really one cause, a blocker against an untested
   milestone.
5. Run it, adopt the recordings, commit both.

`tests/test-eval-suite.sh` runs in the blocking `static` job and fails if a skill
has no case, or if a grader names a skill that no longer exists.

## What the suite does not cover

The plugin's hooks do not fire against mocked tools: a mock is registered as
`mcp__plugin_quality-supervisor_qase__*`, while `hooks.json` matches
`mcp__qase__.*`. Attribution and the destructive-call guards are covered by
`tests/e2e/wire-check.sh` instead.
