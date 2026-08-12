# Quality Supervisor — Plugin Marketplace

Agentic QA **quality-intelligence** for Qase, packaged as an installable plugin
for Claude / Cowork / Claude Code and other MCP-capable AI clients.

This repository is a **plugin marketplace**: colleagues add it once and install
(and update) the `quality-supervisor` plugin from it.

## What's in the plugin

| Component | Name | Purpose |
|-----------|------|---------|
| Skill | `coverage-gap-analysis` | Find untested requirements/suites/critical paths; draft missing cases on approval. |
| Skill | `failure-triage` | Cluster a run's failures, classify bug vs. automation vs. env vs. flaky, create + link defects. |
| Skill | `flakiness-stability` | Quantify flaky/unstable tests; confirm by re-run; recommend quarantine/fix. |
| Skill | `release-readiness` | Five-dimension go / no-go quality gate for a milestone, plan, or release. |
| Agent | `quality-supervisor` | Orchestrator that routes a quality question to the right skill(s). |
| Command | `/quality-report` | Read-only consolidated sweep across all four skills. |

## Install (for your colleagues)

In Claude Code:

```
/plugin marketplace add qase-tms/qase-quality-supervisor
/plugin install quality-supervisor@quality-supervisor
```

In Cowork, install the packaged `.plugin` file directly, or add this repo as a
marketplace if your build supports it.

## Requirements

- **Qase MCP server** — the plugin ships `.mcp.json` that launches
  `@qase/mcp-server` via `npx`. Each user provides their own **`QASE_API_TOKEN`**
  (create at `app.qase.io` → API tokens). For Atlassian Rovo / hosted clients,
  switch `.mcp.json` to the remote OAuth endpoint (the `feat/oauth` build of the
  Qase MCP server).
- A Qase **project code** to target.

Credentials are never bundled — each user authenticates individually.

## Design principles

Qase stays the system of record. Skills read to analyze and only write (cases,
defects, tags, runs) after the user confirms. No skill calls a destructive
(`*_delete`) tool.

## Repository layout

```
.
├── .claude-plugin/
│   └── marketplace.json          # marketplace manifest (lists the plugin)
├── plugins/
│   └── quality-supervisor/       # the plugin itself
│       ├── .claude-plugin/plugin.json
│       ├── .mcp.json
│       ├── agents/
│       ├── commands/
│       ├── skills/
│       └── README.md
└── README.md
```

## License

MIT.
