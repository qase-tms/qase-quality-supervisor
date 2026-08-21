---
name: analyzing-change-impact
description: >-
  Analyze what a feature branch changes and produce a QA-facing impact analysis
  plus a regression/new checklist, grounded in the project's existing Qase cases.
  Use when the user asks for an impact analysis, change impact, risk analysis, or
  blast radius of a branch or PR; what QA should test for these changes; a QA
  checklist or test plan for a branch; what could break; or which existing tests
  to re-run before merging. Reads the repository diff and Qase; renders an HTML
  report.
---

# Analyzing Change Impact

Turn a branch diff into a **QA-facing report**: what is affected in user and consumer
terms, and what to verify before merging. No implementation details — it is written
for a QA engineer, not for code review.

The report has two parts:

- **QA Impact Analysis** — affected user-facing scenarios, and the public/external
  API *only when the change actually reaches it*.
- **QA Checklist** — numbered, split into **Regression** (existing stable behaviour
  the change reaches into, grounded in existing **manual / to-be-automated** Qase
  cases; automated ones excluded) and **New** (what this branch adds or changes).

Repository-agnostic: infer the stack from the repo rather than assuming one.

## Prerequisites

- A **git repository** with a branch that differs from its default branch. This is
  the only skill here that reads source code rather than only Qase.
- A **project code** for the Qase project holding the reference cases. If the user
  didn't give one, ask — never guess. Teams often keep one shared project for this;
  ask once and reuse it for the run.
- QQL access (Business/Enterprise) for the coverage step.
- **Read `references/qql.md` before composing any QQL query.** Field names are not
  uniform across entities, and a wrong one is a hard error rather than an empty
  result.

## Tools

- `qase_project_context` — project metadata and the suite tree. Call first.
- `qql_search` — find candidate cases and filter by automation state.
- `qase_get` — read a matched case's steps to confirm it covers the area.
- `Bash`, `Read`, `Grep`, `Glob` — the diff and the code.

Read-only on Qase throughout: this skill never creates or edits cases, defects, or
runs. The bundled `PreToolUse` guard blocks destructive calls outright, so that is
enforced rather than merely promised.

## Step 1: Find the base branch and collect the diff

Fetch first, so you diff against the actual remote rather than a stale local ref:

```bash
git fetch origin
```

Determine the default branch — do not assume `main` or `master`. Local first, network
only if needed:

```bash
# 1. Local: the remote HEAD ref (set by clone / `git remote set-head`)
base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
# 2. Network fallback: ask the remote directly
[ -z "$base" ] && base=$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')
# 3. Last resort: detect main/master locally
[ -z "$base" ] && git rev-parse --verify origin/main   >/dev/null 2>&1 && base=main
[ -z "$base" ] && git rev-parse --verify origin/master >/dev/null 2>&1 && base=master
echo "$base"   # empty → ask the user
```

Each check is a separate statement, and emptiness — not an exit code — triggers the
next fallback: a pipe through `sed` always reports success, so `||` chaining would
not work here. If none yields a branch, ask for the base branch rather than guessing.

Then collect, using `origin/<base>` everywhere (never a local branch — it may be
stale):

```bash
git diff origin/<base>...HEAD              # the diff: the only reliable source
git diff --name-only origin/<base>...HEAD  # changed files
git diff --stat origin/<base>...HEAD       # size, before reading it whole
git branch --show-current                  # for the report header
git rev-parse --short HEAD                 # provenance
```

The triple dot compares the merge-base to HEAD, which is exactly "what this branch
adds" regardless of merges, rebases, or squash-merged sub-branches. **Base the
analysis on the diff, never on commit messages** — squash-merge workflows leave
orphan commits that describe work already shipped elsewhere.

If the diff is empty, the branch adds nothing — say so and stop.

## Step 2: Identify the project's surfaces

Infer the stack from the repo: manifest and build files (`composer.json`,
`package.json`, `go.mod`, `pyproject.toml`, `Cargo.toml`, `pom.xml`), route files and
entrypoints, OpenAPI/proto specs, the layering (controllers, services, repositories,
models, migrations, middleware, jobs, listeners), and the frontend tree.

From that, decide which surfaces the change can touch:

| Surface | What it is | How users/consumers notice |
|---|---|---|
| User-facing UI | Web/mobile/desktop screens | A scenario in the app behaves differently |
| Public / external API | REST/GraphQL/gRPC endpoints, webhooks, published events | A consumer's request/response changes |
| Library / SDK public API | Exported functions, types, CLI flags | Downstream code that imports it changes |
| Background / async | Jobs, queues, cron, workers, listeners | Something happens, or stops, out of band |
| Cross-cutting | Middleware, auth, config, migrations, shared utils | Several of the above change at once |

## Step 3: Analyze what changed

**Size the diff before reading it whole.** A large branch can exceed the context
window, and a silently truncated diff produces a confidently wrong analysis.

- Small or medium diff → read it whole.
- Large diff (roughly >2000 changed lines or >40 files — judgement, not a hard
  cutoff) → group the changed files by subsystem and dispatch parallel Explore
  agents, one per group, each returning a behaviour summary; then synthesize. Never
  analyze the first N files and treat the rest as unchanged. If you cannot cover
  everything, say so in the report.

For each change, establish: what **behaviour** changed (not which lines), which layer
it sits in, which surfaces it reaches, and whether it is new or existing. Mark added
or changed behaviour `[NEW]` / `[BREAKING]`; the existing behaviour it reaches into is
the stable surface Step 4 grounds in Qase. A single surface is often both — an
existing endpoint gaining a field needs regression *and* new checks.

For removed or deprecated behaviour, flip the angle: verify nothing still depends on
it and that it is actually gone, rather than that it "works". Flag `[BREAKING]`.

### Trace transitive callers for shared code

Changes to shared code — services, repositories, utilities, models, formatters,
domain logic — almost always affect **multiple** surfaces. A file is not "UI-only"
because that is where you first saw it used.

**Trace callers for every changed non-entrypoint file:**

1. Take the changed symbol (short name, not the fully-qualified one).
2. Grep it across the whole codebase to find every consumer.
3. Follow the chain: changed symbol → service that uses it → entrypoint that
   exposes it.
4. One shared change can land in several surfaces at once — list it in each.

Use parallel Explore agents when you need this depth. **Never conclude "no public API
affected" — or "UI-only", or "internal-only" — without having traced every changed
shared symbol to its consumers.** Reachability is decided by tracing, not by whether
a spec file changed: a code-only change to shared internals can reach a public
endpoint with no spec diff at all.

## Step 4: Ground regression in existing Qase coverage

Once you know which **stable** areas the change reaches, read the cases that already
cover them, so Regression reflects real coverage instead of guesswork.

Read in a **bounded, narrowing** order — the project may be large:

1. `qase_project_context` once, for the suite tree. Shortlist only suites whose
   name or scope fits an affected area.
2. `qql_search` for cases in those suites whose titles match the affected
   functionality:

   ```
   entity = "case" and project = "CODE" and suite in ["Suite A", "Suite B"]
   ```

   **Do not decide automation state from a QQL predicate.** QQL's copy of
   `automation` can lag the live case — measured eleven days behind on a real
   workspace, calling automated cases manual — so `automation = "Manual"` will hand
   you cases a human no longer runs. Read `automation` from the full entity instead
   (`0` Manual, `1` To be automated, `2` Automated); that value is the live one. When
   a case decides whether a whole area needs a manual check, confirm it with
   `qase_get`. Also **deduplicate by case id** — row queries can return the same case
   twice — and remember `suite = "X"` matches *every* suite with that title, which may
   be more than the one you meant. `references/qql.md` has the evidence for all three.

3. `qase_get` on the matched cases, to confirm from the steps that they actually
   cover the area — not by title alone.

**Cap the reads:** roughly 5–8 suites and 30 cases per run. If an area genuinely
needs more, note that rather than silently reading hundreds of cases. The point is to
inform the checklist, not to mirror the project.

**Exclude already-automated cases from Regression.** Ground it only on cases that are
**manual** or **to be automated** — the ones a human still has to run. Take that from
each case's live `automation` field, per step 2, not from a QQL predicate. If an
affected area's only coverage is automated, it needs no manual regression item, and
that is **not** a coverage gap. A coverage gap is an area with **no** cases at all.

**Do not list or quote the cases.** They are input to your reasoning; the checklist is
written in your own words as self-contained checks. Track which suites you consulted —
they go in the closing note.

If QQL is unavailable (permission error on a lower plan), say so and produce the
report with Regression derived from the diff alone, clearly labelled as ungrounded —
a stated limitation beats a silent one.

## Step 5: Requirements, when they are available

If the branch name embeds a ticket key and a ticket tracker is connected, read the
ticket's acceptance criteria and compare them against the diff. Flag `[MISMATCH]` for
anything required but missing, or implemented but not requested.

```bash
git branch --show-current | grep -oiE '[A-Z][A-Z0-9]+-[0-9]+' | tr '[:lower:]' '[:upper:]' | sort -u
```

This lists **all distinct** candidates rather than silently taking the first, so the
ambiguous case is detectable: one line → the candidate; zero or several → ask, or
proceed without. The regex also matches non-tickets (`release-2024` → `RELEASE-2024`),
so treat any match as a candidate that only a successful read confirms.

Requirements are **optional context, not a precondition.** With no tracker connected,
no key in the branch name, or no readable ticket: emit **no** `[MISMATCH]` flags and
note once in the report that requirement-versus-implementation could not be checked.
Never block the report on this.

## Step 6: The report

Two parts. Audience is QA: describe what the user or consumer sees, never how it is
built — no class names, package names, library versions, or file lists. Group related
changes: five files supporting one scenario is one item. Skip trivia — formatting,
import order, comment-only edits, type hints that change no behaviour.

### Part 1 — QA Impact Analysis

Open with a short plain-language summary (3–5 sentences): what the branch changes and
what the user or consumer notices. Reviewers read this first, so always keep it. Then,
only when there is a genuine `[MISMATCH]`, a bullet per mismatch phrased so the author
can confirm intent — do not enumerate de-scoped criteria to note they were correctly
not done.

Part 1 has at most **two** sections:

| Surface from Step 2 | Part 1 section |
|---|---|
| User-facing UI | **1. User-Facing** — always present |
| Public / external API | **2. Public / External API** — only when reached |
| Library / SDK public API | **2. Public / External API** (the exported contract is the consumer surface) |
| Background / async | *no Part 1 section* — verified in the checklist |
| Cross-cutting | fold into the two above if it surfaces there; otherwise the checklist |

**User-Facing is always present**; if nothing is user-facing, keep the heading and say
so plainly. **Public / External API is included only when tracing shows the change
reaches a public surface** — omit the whole section otherwise, no placeholder. An
internal, session-authenticated endpoint is not a public API: its user-visible effect
belongs under User-Facing.

There is **no infrastructure section**. Background jobs, queues, cron, migrations and
integrations are verified in the checklist, not described here.

### Part 2 — QA Checklist

A flat **numbered** list in exactly two blocks. Do not subdivide by surface — one list
per block, covering all surfaces together. Every check is concrete: an action plus the
observable expected result. Do not repeat between blocks.

- **Regression** — existing stable behaviour the change reaches into, grounded only in
  the manual / to-be-automated cases from Step 4, in your own words, no case IDs.
  Where an affected area has no cases at all, add an item flagged
  **Coverage gap:** `<area>` — no existing cases.
- **New** — what this branch adds or changes (`[NEW]`, `[BREAKING]`, `[MISMATCH]`),
  grounded in acceptance criteria when available, plus key negative and edge cases.
  This comes from Step 3, not from Qase.

Close with a short note naming the areas that need new or updated automated tests, and
recording provenance: the suites consulted, that automated cases were excluded, and
that Qase was read-only. If every affected area already has adequate coverage, say
that plainly rather than inventing gaps.

## Step 7: Render the report

**Read `assets/impact-template.html` and produce a filled copy** — same visual
language as the other reporting skill in this plugin. Keep the header chips (branch,
base, commit, and the ticket when known), the summary, both parts, and the provenance
footer.

Save as `impact-analysis-<branch>-<YYYY-MM-DD>.html` in the current working directory,
unless the user named a destination — then use theirs. Sanitise the branch name for
the filename (slashes become dashes). Never write outside that directory, and if the
file already exists, say so and ask before overwriting.

State the path when you hand it over: in a terminal client the path is the
deliverable; in a client that renders files, present it there as well. Keep the
closing message short.

### Posting to a ticket — only when asked

**Do not post anything anywhere by default.** The report is a local file.

If the user explicitly asks for it on the ticket, and a tracker MCP is connected, add
a **single comment** — and only then. Three rules, because this step leaves the
machine:

1. **Confirm the target first.** Show the ticket key and ask before posting. A
   comment added through an MCP typically **cannot be edited or deleted afterwards**,
   so a wrong-ticket post is irreversible.
2. **Add only a comment.** Never change status, assignee, labels, or any other field.
   On a re-run, add a fresh comment — do not attempt to edit or delete an earlier one.
3. **Mark it as AI-generated**, tied to branch, commit and a UTC timestamp:
   `_Auto-generated QA impact analysis · branch <name> · commit <sha> · <timestamp> — review before relying on it._`

If posting fails, never discard the work: the HTML file already exists — say where it
is and what failed.

## Honesty notes

- Coverage from Qase describes **known, stable** behaviour. Anything `[NEW]` or
  `[BREAKING]` has no existing case by definition, so those checks come from the diff
  analysis alone. Existing coverage informs Regression; it never proves new behaviour
  is covered.
- If you could not read the whole diff, say which parts you skipped. A partial
  analysis presented as complete is worse than an admitted gap.
- Reachability claims are only as good as the tracing behind them. If you could not
  trace a shared symbol to its consumers, say so instead of concluding a surface is
  unaffected.
