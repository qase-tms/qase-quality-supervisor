# Quality Supervisor

Agentic QA **quality-intelligence** for Qase, delivered as an installable
plugin for Claude Desktop / Cowork / Claude Code (and other MCP-capable AI
clients such as Cursor, VS Code, or Atlassian Rovo) — while Qase stays the
system of record.

It closes the "quality skills" gap between simple test-data CRUD and the
higher-order analysis competitors demo: coverage, triage, flakiness, and
release readiness.

This repository is both the plugin **and** its plugin marketplace: colleagues
add it once and install (and update) `quality-supervisor` from it.

## What's inside

| Component | Name | Purpose |
|-----------|------|---------|
| Skill | `finding-coverage-gaps` | Find untested requirements/suites/critical paths; draft missing cases on approval. |
| Skill | `triaging-test-failures` | Cluster a run's failures, classify bug vs. automation vs. env vs. flaky, create + link defects. |
| Skill | `analyzing-test-flakiness` | Quantify flaky/unstable tests via history + `isFlaky`; confirm by re-run; recommend quarantine/fix. |
| Skill | `assessing-release-readiness` | Five-dimension go / no-go quality gate for a milestone, plan, or release. |
| Agent | `quality-supervisor` | Orchestrator that routes a quality question to the right skill(s) and rolls up results. |
| Command | `/quality-supervisor:quality-report` | Read-only consolidated sweep: coverage + flakiness + triage + readiness. |

**New here? [QUICKSTART.md](QUICKSTART.md)** takes you from install to a first
report, and explains how to read one.

## Install

In Claude Code:

```
/plugin marketplace add qase-tms/qase-quality-supervisor
/plugin install quality-supervisor@quality-supervisor
```

After a restart, `/plugin` reports the inventory as **5 skills, 1 agent, 1
PreToolUse hook**. Five because the CLI counts the `quality-report` command under
`Skills`; four skills plus one command is what actually ships.

In Cowork, install the packaged `.plugin` file directly, or add this repo as a
marketplace if your build supports it.

## Requirements

- **Qase MCP server.** This repo ships `.mcp.json` pointing at the hosted,
  OAuth-authenticated endpoint (`https://mcp.qase.io/mcp`), so there is no API
  token to create or store — your client runs the OAuth flow on first use and
  you authorise with your normal Qase login. Credentials are never bundled and
  never enter the repo.
- A Qase **project code** to target.
- **Plan:** the hosted endpoint requires an **Enterprise** subscription, and the
  skills' analysis relies on QQL, which requires **Business or Enterprise**. On
  a Business plan, use the local server instead (below).

### Running the MCP server locally instead

Useful on Business plans, for development, or where the hosted endpoint isn't
reachable. Replace `.mcp.json` with:

```json
{
  "mcpServers": {
    "qase": {
      "command": "npx",
      "args": ["-y", "@qase/mcp-server"],
      "env": {
        "QASE_API_TOKEN": "${QASE_API_TOKEN}",
        "QASE_MCP_INTEGRATION": "quality-supervisor/0.1.1"
      }
    }
  }
}
```

Then set `QASE_API_TOKEN` in your environment (create one at `app.qase.io` →
API tokens). Keep the server name `qase` — the bundled guard hooks match tool
names by that prefix, and renaming it silently disables them.

`QASE_MCP_INTEGRATION` is the self-run equivalent of the `X-Qase-Integration`
header the hosted configuration sends: it tells Qase that these calls came from
this plugin, so usage can be counted per team. It carries this plugin's name and
version and nothing else — see [SECURITY.md](SECURITY.md). Attribution needs
**MCP server 2.2.2 or newer**; older servers ignore the variable, and dropping it
costs you nothing but the count.

The skills expect **MCP server 2.1.1 or newer**. Earlier versions ship broken QQL
examples in the tool schema — which the model copies and the API rejects — and,
before 2.1.0, a `qase_triage_defect` that reported linking it never performed.

> The skills are written against the consolidated Qase MCP tool surface
> (`qase_project_context`, `qql_search`, `qase_get`, `qase_case_upsert`,
> `qase_triage_defect`, `qase_regression_run`, `qase_ci_report`,
> `qase_defect_upsert`, `qase_result_record`, `qase_discover_tools`,
> `qase_suite_upsert`, `qase_run_upsert`, `qase_api`, plus `qql_help`). Non-core
> tools — among them `qase_case_bulk_create`, `qase_milestone_upsert`, and
> `qase_external_issue_link` — must be activated on demand via
> `qase_discover_tools`, or the call fails as an unknown tool. That split belongs
> to the server and can move with a server release; it was last verified on
> 2026-08-18.

## Design principles

- **Qase is the system of record.** Skills read to analyze; they write (cases,
  defects, tags, runs) only after you confirm.
- **Evidence-backed.** Every finding shows the QQL behind it.
- **Non-destructive, enforced.** No skill calls a `*_delete` tool — and a
  bundled `PreToolUse` hook blocks such calls outright, including a `DELETE`
  issued through the `qase_api` escape hatch. This is a technical guard, not
  just a prompt-text promise, and it is tested end to end against a live server.
  See [SECURITY.md](SECURITY.md).
- **Human-in-the-loop.** Bulk writes require a sample and a yes first.

## Usage examples

Ask in your own words — the skills pick themselves up from the question:

- "Where are our coverage gaps in project WEB?"
- "Triage the latest run in WEB and tell me what's a real bug."
- "What's our flake rate this month and which tests should we quarantine?"
- "Which suites are empty?" · "Which cases are still manual?"
- "Are we ready to ship milestone 2.3?" · "What's blocking the release?"

### When you want a guarantee, use the command

Phrasing picks a skill through the model's judgement, and that judgement is not
deterministic: measured over 180 runs, the right skill fires for a natural
question about 91% of the time. It never fires the *wrong* one — but it does
occasionally answer without it.

`/quality-supervisor:quality-report <PROJECT> [milestone|plan|run]` always runs,
because a command is an explicit instruction rather than a routing decision.
Plugin commands are namespaced by the plugin, so the prefix is required — a bare
`/quality-report` is reported as an unknown command. Reach for it when you
need the sweep to happen — in a release checklist, a scheduled job, or anything
where "it usually triggers" isn't good enough.

Naming the domain helps too: "which suites are empty **in Qase**" routes more
reliably than the same question without it, because a bare "suites" or "release"
could belong to any tool.

**Any single skill can also be invoked directly**, which bypasses routing the same
way the command does:

```
/quality-supervisor:analyzing-test-flakiness
/quality-supervisor:triaging-test-failures
/quality-supervisor:finding-coverage-gaps
/quality-supervisor:assessing-release-readiness
```

Use these when you want one specific analysis rather than the whole sweep, and
want it to happen for certain.

### Model choice matters for routing, not for the analysis

Measured on Haiku, the right skill fires for a natural question 58% of the time
against 90% on a larger model — while the analysis itself holds up (a
never-passing test is still called a regression rather than a flake, the blocking
defect is still named). So on a smaller model the skills still do their job
correctly; they just need to be asked explicitly.

If you run this on Haiku, invoke explicitly — the command for a full sweep, or
`/quality-supervisor:<skill-name>` for one analysis. Both bypass routing entirely,
which is the part that degrades.

## Repository layout

```
.
├── .claude-plugin/
│   ├── marketplace.json   # marketplace manifest (lists this plugin, source ".")
│   └── plugin.json        # plugin manifest
├── .githooks/
│   └── pre-commit         # opt-in version-sync check (see docs/releasing.md)
├── .github/workflows/
│   └── validate.yml       # CI: manifest validation, secrets scan, hook tests
├── .mcp.json               # Qase MCP server wiring, incl. the integration marker
├── agents/
│   └── quality-supervisor.md
├── commands/
│   └── quality-report.md
├── docs/
│   ├── gui-smoke-check.md  # 10-minute manual check per GUI client
│   ├── releasing.md        # version bumps, the pre-commit hook, release checks
│   └── superpowers/        # design specs and plans behind each iteration
├── hooks/
│   ├── hooks.json          # PreToolUse guards against destructive calls
│   ├── deny-destructive.sh
│   └── deny-destructive-api.sh
├── references/
│   └── qql.md              # verified QQL field/enum reference the skills read
├── scripts/
│   ├── verify-plugin.sh    # local verification (also run by CI)
│   ├── check-version-sync.sh  # asserts every copy of the version agrees
│   └── set-version.sh      # bumps all four copies in one command
├── skills/
│   ├── finding-coverage-gaps/
│   ├── triaging-test-failures/
│   ├── analyzing-test-flakiness/
│   └── assessing-release-readiness/
├── tests/
│   ├── test-deny-destructive.sh
│   └── test-version-sync.sh
├── CHANGELOG.md
├── LICENSE
├── QUICKSTART.md           # install -> first report
├── README.md
└── SECURITY.md             # data flow, boundaries, what is verified
```

`references/qql.md` is not optional reading material: every skill is instructed to
read it before composing a query, because QQL field names differ per entity and a
wrong name is a hard error rather than an empty result.

## Notes

"Quality Supervisor" is the plugin/agent name. It composes the four skills into
one quality workflow; each skill also works standalone when triggered directly.

## License

MIT.
