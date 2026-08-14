# Quickstart

From nothing to your first quality report. Four steps, and the only one that
takes real time is the authorisation click.

## Before you start

- A Qase project you can read, and its **project code** — the short uppercase
  prefix on your case IDs (`DEMO-42` → `DEMO`).
- A Qase plan of **Business or Enterprise**. The analysis runs on QQL, which
  lower plans don't include. The hosted connection additionally needs
  **Enterprise**; on Business, use the local server in step 2b.

## 1. Install the plugin

In Claude Code:

```
/plugin marketplace add qase-tms/qase-quality-supervisor
/plugin install quality-supervisor@quality-supervisor
```

Restart the session so the skills load.

Check it took:

```
/plugin
```

You should see `quality-supervisor` enabled, with four skills, one agent and one
command.

## 2. Connect to Qase

### 2a. Hosted — the default, no token

Nothing to configure. The first time a skill needs Qase, your client opens the
OAuth flow; authorise with your normal Qase login. The plugin never sees or
stores a credential.

If the flow doesn't start, the usual cause is a client that can't open a browser
(a headless or remote session). Use 2b there.

### 2b. Local — for Business plans, or headless

Create a token at `app.qase.io` → **Settings → API tokens**, put it in your
environment, and replace `.mcp.json` with:

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

Keep the server name `qase`. The bundled guards match tool names by that prefix,
and renaming it disables them silently.

## 3. Get your first report

```
/quality-supervisor:quality-report DEMO
```

Substitute your project code. This runs the full read-only sweep — coverage,
flakiness, triage of the latest run, and release readiness if you scope it — and
writes nothing.

Expect a couple of minutes on a large project: it is issuing real queries.

## 4. Read it properly

The report has a section most tools don't print, and it is the one to read first:

**Data confidence.** It lists what could not be measured — a truncated
collection, an empty time window, metadata nobody fills in, a disagreement
between two sources. A gap named there is a gap in the *evidence*, not a clean
result. If it says defect tracking isn't in use, "no blocking defects" means
nobody is recording them, not that none exist.

Two other habits worth having:

- **Every number has a denominator.** "40 cases aren't automated" reads very
  differently against 50 cases than against 18,000, so the report always gives
  both.
- **Flaky and failing are different findings.** A test that both passes and fails
  is flaky — quarantine or fix the test. A test that only ever fails is a
  regression — fix the product. The report separates them, and acting on the wrong
  one wastes the work.

## Asking in your own words

You don't need the command. These route to the right skill on their own:

- "Where are our coverage gaps in DEMO?"
- "Which DEMO tests are flaky?"
- "Triage the latest DEMO run."
- "Are we ready to ship milestone 2.3 in DEMO?"

Routing is a judgement the model makes, and it is not perfectly reliable —
measured at about 90% for natural phrasings, less on smaller models. It never
picks the *wrong* skill; it occasionally answers without one. When you need
certainty, name the skill:

```
/quality-supervisor:analyzing-test-flakiness
/quality-supervisor:triaging-test-failures
/quality-supervisor:finding-coverage-gaps
/quality-supervisor:assessing-release-readiness
```

## Writing back to Qase

The sweep is read-only. Skills can also draft cases, file defects, tag flaky
tests, and create runs — but only after you approve, and bulk changes only after
you've seen a sample. Ask directly:

- "Draft the missing cases for the billing suite."
- "File defects for the real bugs in run 512."
- "Flag those flaky tests in Qase."

Deletion is blocked outright, in code, and cannot be approved. See
[SECURITY.md](SECURITY.md).

## If something doesn't work

| Symptom | Cause |
|---|---|
| `Unknown command: /quality-report` | the prefix is required: `/quality-supervisor:quality-report` |
| A skill answers "no access to Qase data" | the MCP server isn't connected or authorised — step 2 |
| "QQL is only available in Business and Enterprise" | plan limitation; there is no workaround in the plugin |
| A question gets a general answer, no analysis | routing missed; name the skill or use the command |
| Suite or milestone lists look short | `qase_project_context` caps at 100 per collection and says so; treat them as a sample |
| Numbers disagree with the Qase UI | expected on older projects — the search index has no historical backfill. The report flags it under Data confidence |

## Next

- [README.md](README.md) — what each skill does, and the design principles
- [SECURITY.md](SECURITY.md) — data flow, boundaries, what is and isn't verified
- [evals/README.md](evals/README.md) — the test harness, if you want to check any
  of the above yourself
