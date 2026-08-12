# Quality Supervisor

Agentic QA **quality-intelligence** for Qase, delivered as AI-client skills. The
plugin turns any MCP-capable AI client (Claude, Cursor, VS Code, Atlassian Rovo,
etc.) into a quality supervisor over your Qase project — while Qase stays the
system of record.

It closes the "quality skills" gap between simple test-data CRUD and the
higher-order analysis competitors demo: coverage, triage, flakiness, and
release readiness.

## What's inside

| Component | Name | Purpose |
|-----------|------|---------|
| Skill | `coverage-gap-analysis` | Find untested requirements/suites/critical paths; draft missing cases on approval. |
| Skill | `failure-triage` | Cluster a run's failures, classify bug vs. automation vs. env vs. flaky, create + link defects. |
| Skill | `flakiness-stability` | Quantify flaky/unstable tests via history + `isFlaky`; confirm by re-run; recommend quarantine/fix. |
| Skill | `release-readiness` | Five-dimension go / no-go quality gate for a milestone, plan, or release. |
| Agent | `quality-supervisor` | Orchestrator that routes a quality question to the right skill(s) and rolls up results. |
| Command | `/quality-report` | Read-only consolidated sweep: coverage + flakiness + triage + readiness. |

## Requirements

- **Qase MCP server** connected in your AI client. Configured in `.mcp.json` to
  launch `@qase/mcp-server` via `npx`, authenticated with a `QASE_API_TOKEN`
  environment variable (create a token at `app.qase.io` → API tokens).
- A Qase **project code** to target.

> The skills are written against the consolidated Qase MCP tool surface
> (`qase_project_context`, `qql_search`, `qase_get`, `qase_case_upsert`,
> `qase_triage_defect`, `qase_regression_run`, `qase_ci_report`,
> `qase_defect_upsert`, `qase_result_record`, `qase_discover_tools`,
> `qase_api`, plus `qql_help`). Non-core tools are activated on demand via
> `qase_discover_tools`.

### OAuth / remote deployment (Rovo & hosted clients)

For Atlassian Rovo and other hosted clients, point `.mcp.json` at the remote,
OAuth-authenticated Qase MCP endpoint instead of the local `npx` command once
it is available in your environment (the `feat/oauth` build of the Qase MCP
server adds remote OAuth transport). No API token is stored in that mode — the
client performs the OAuth flow.

## Design principles

- **Qase is the system of record.** Skills read to analyze; they write (cases,
  defects, tags, runs) only after you confirm.
- **Evidence-backed.** Every finding shows the QQL behind it.
- **Non-destructive.** No skill calls a `*_delete` tool.
- **Human-in-the-loop.** Bulk writes require a sample and a yes first.

## Usage examples

- "Where are our coverage gaps in project WEB?"
- "Triage the latest run in WEB and tell me what's a real bug."
- "What's our flake rate this month and which tests should we quarantine?"
- "Are we ready to ship milestone 2.3?" or `/quality-report WEB 2.3`

## Notes

"Quality Supervisor" is the plugin/agent name. It composes the four skills into
one quality workflow; each skill also works standalone when triggered directly.
