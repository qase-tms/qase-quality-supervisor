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
| Skill | `coverage-gap-analysis` | Find untested requirements/suites/critical paths; draft missing cases on approval. |
| Skill | `failure-triage` | Cluster a run's failures, classify bug vs. automation vs. env vs. flaky, create + link defects. |
| Skill | `flakiness-stability` | Quantify flaky/unstable tests via history + `isFlaky`; confirm by re-run; recommend quarantine/fix. |
| Skill | `release-readiness` | Five-dimension go / no-go quality gate for a milestone, plan, or release. |
| Agent | `quality-supervisor` | Orchestrator that routes a quality question to the right skill(s) and rolls up results. |
| Command | `/quality-report` | Read-only consolidated sweep: coverage + flakiness + triage + readiness. |

## Install (for your colleagues)

In Claude Code:

```
/plugin marketplace add qase-tms/qase-quality-supervisor
/plugin install quality-supervisor@quality-supervisor
```

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
      "env": { "QASE_API_TOKEN": "${QASE_API_TOKEN}" }
    }
  }
}
```

Then set `QASE_API_TOKEN` in your environment (create one at `app.qase.io` →
API tokens). Keep the server name `qase` — the bundled guard hooks match tool
names by that prefix, and renaming it silently disables them.

The skills expect **MCP server 2.1.0 or newer**. Earlier versions ship a broken
QQL example in the tool schema and a `qase_triage_defect` that reports linking
it never performed.

> The skills are written against the consolidated Qase MCP tool surface
> (`qase_project_context`, `qql_search`, `qase_get`, `qase_case_upsert`,
> `qase_triage_defect`, `qase_regression_run`, `qase_ci_report`,
> `qase_defect_upsert`, `qase_result_record`, `qase_discover_tools`,
> `qase_api`, plus `qql_help`). Non-core tools are activated on demand via
> `qase_discover_tools`.

## Design principles

- **Qase is the system of record.** Skills read to analyze; they write (cases,
  defects, tags, runs) only after you confirm.
- **Evidence-backed.** Every finding shows the QQL behind it.
- **Non-destructive, enforced.** No skill calls a `*_delete` tool — and a
  bundled `PreToolUse` hook blocks such calls outright, including a `DELETE`
  issued through the `qase_api` escape hatch. This is a technical guard, not
  just a prompt-text promise.
- **Human-in-the-loop.** Bulk writes require a sample and a yes first.

## Usage examples

- "Where are our coverage gaps in project WEB?"
- "Triage the latest run in WEB and tell me what's a real bug."
- "What's our flake rate this month and which tests should we quarantine?"
- "Are we ready to ship milestone 2.3?" or `/quality-report WEB 2.3`

## Repository layout

```
.
├── .claude-plugin/
│   ├── marketplace.json   # marketplace manifest (lists this plugin, source ".")
│   └── plugin.json        # plugin manifest
├── .github/workflows/
│   └── validate.yml       # CI: manifest validation, secrets scan, hook tests
├── .mcp.json               # Qase MCP server wiring
├── agents/
│   └── quality-supervisor.md
├── commands/
│   └── quality-report.md
├── hooks/
│   ├── hooks.json          # PreToolUse guards against destructive calls
│   ├── deny-destructive.sh
│   └── deny-destructive-api.sh
├── scripts/
│   └── verify-plugin.sh    # local verification (also run by CI)
├── skills/
│   ├── coverage-gap-analysis/
│   ├── failure-triage/
│   ├── flakiness-stability/
│   └── release-readiness/
├── tests/
│   └── test-deny-destructive.sh
├── CHANGELOG.md
├── LICENSE
└── README.md
```

## Notes

"Quality Supervisor" is the plugin/agent name. It composes the four skills into
one quality workflow; each skill also works standalone when triggered directly.

## License

MIT.
