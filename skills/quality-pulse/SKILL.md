---
name: quality-pulse
description: >-
  Build a visual "Quality Pulse" report card for a Qase project over any period
  the user chooses — daily, weekly, biweekly, monthly, sprint, or a custom date
  range. A styled HTML card summarizing test execution, pass rate, defect
  backlog, case activity, and active users for that window. Use this whenever the
  user asks for a quality pulse, QA pulse, quality/test report card, test health
  summary, sprint QA snapshot, release health check, or any "how is testing
  going" overview for a Qase project over some period, even if they don't say the
  word "pulse".
---

# Quality Pulse

Turn raw Qase data into a single, skimmable HTML **report card** that answers "how healthy is QA over this period?" — execution, pass rate, defect backlog, what changed in the test repository, and who was active.

The period is whatever the user wants — a single day, a week, two weeks, a month, a sprint, or an explicit date range. Everything in the card is scoped to that window, and the window is shown prominently so the reader always knows what they're looking at.

The output is one self-contained HTML file (no external dependencies) that the user can open, screenshot, or drop into a status update. A finished reference lives in `assets/pulse-template.html` — clone its look and structure, swap in the real numbers.

## When to use

Trigger on requests like "quality pulse for project X", "QA report card for the last month", "how's testing looking this sprint", "daily test health for WEB", "biweekly quality snapshot", "release health for the 2.0 milestone". If the user just asks a narrow one-off question ("what's the pass rate of run 42?"), answer that directly instead — the pulse is for the periodic, multi-metric overview.

This is a **period overview**, not a scoped release decision. "Are we ready to ship milestone 2.3?" belongs to `assessing-release-readiness`, which weighs a named scope against a gate. The pulse describes a window of time and grades it; it never says go or no-go.

## Prerequisites

- A **project code**. If the user didn't give one, ask — never guess.
- QQL access (Business/Enterprise) for the case-activity counts. If `qql_search`
  returns a permission error, say so and report the rest of the card without the
  new/updated case tiles rather than dropping the whole pulse.
- **Read `references/qql.md` before composing any QQL query.** Field names are not
  uniform across entities, and a wrong one is a hard error rather than an empty
  result.

## Step 1 — Scope the report

Settle two things before pulling data (ask if either is unclear — don't guess a project):

1. **Which project?** If unsure, list projects with `qase_api GET /v1/project?limit=100` and show titles + codes + case/run/defect counts so the user can pick.
2. **What period?** This skill is period-agnostic — honor whatever cadence the user asks for and translate it into a concrete start/end date pair:
   - "today" / "daily" → last 1 day
   - "this week" / "weekly" → last 7 days
   - "biweekly" / "fortnightly" / "last two weeks" → last 14 days
   - "monthly" / "this month" / "last 30 days" → last 30 days (or the calendar month if they say "March")
   - "this sprint" → ask for the sprint length or milestone if not obvious
   - an explicit range ("May 1–15", "since the 2.0 release") → use it verbatim
   - **If they don't specify, default to the last 14 days** and state that in the card so the scope is never ambiguous.

   Always resolve to an actual `[start, end]` in UTC (check today's real date; Qase timestamps are UTC). Everything below is filtered to that window. Put the resolved range in the card's **Window** chip and repeat it in the footnote.

## Step 2 — Gather the data

Pull these, scoped to the project code and the resolved window. Key gotchas are noted — they save real time.

- **Project standing:** `qase_project_context` (code) → total cases, suites, milestones, run counts, defect counts, and the **users** list (id → name → title). Cache this; it seeds most labels.
- **Runs in window:** `qase_api GET /v1/run/{CODE}` with `limit`/`offset`.
  - **Gotcha:** the run list is sorted by **id ascending**, so the *most recent* runs are at the *highest offset* (near `total`), not offset 0. Page from the end — fetch the last page (`offset = total - limit`), and keep paging backwards until a run's `start_time` falls before your window start. `limit` is **capped at 100** on this endpoint — don't request more or it errors.
  - Read each run's `start_time` and `stats` (`passed`/`failed`/`untested`/`in_progress`/etc.).
- **Defects:** `qase_api GET /v1/defect/{CODE}?limit=100`. Count `status == "open"` (standing backlog); count how many were `created_at` inside the window (new this period); tally high-severity open defects (`severity` in blocker/critical).
- **New / updated cases:** use QQL — it supports date attributes on cases (unlike runs). Use the resolved window start:
  - `entity = "case" and project = "CODE" and created >= "YYYY-MM-DD"` → new cases
  - `entity = "case" and project = "CODE" and updated >= "YYYY-MM-DD"` → touched cases
  - For a bounded range also add `and created <= "YYYY-MM-DD"`.
  - **Gotcha:** QQL does **not** expose a `created` attribute on the `run` entity — don't filter runs by date in QQL; use run `start_time` from the REST list instead.
- **Active users:** collect the distinct `user_id` (runs) and `member_id` (defects, cases) that appear inside the window, then resolve each to a name/title via the `qase_project_context` users list, or `qase_get entity="user" id=<id>` for ids not in the first page. Note what each did (ran suites, filed defects, authored cases).

If the MCP connector times out on a call, just retry it once — these servers occasionally drop a request.

## Step 3 — Compute the metrics

All metrics are scoped to the resolved window.

- **Runs** = count of runs whose `start_time` is in the window.
- **Results executed** = sum of non-untested, non-in-progress result statuses across those runs. **Pass rate = passed / executed** — exclude untested/in-progress so the number reflects real signal, and say so in the footnote.
- **New defects** = defects created in window. **Open defects** = current open backlog (standing, not just this period). Call out **high-severity open** (blocker + critical) — that's usually the story.
- **New cases / updated cases** = QQL counts above.
- **Active users** = the resolved list with a one-line "what they did" each.
- **Health grade** (heuristic letter, A–D): reward green execution and a healthy pass rate; penalize a large or aging defect backlog and flat/zero activity. Keep it honest — an active project drowning in open blockers is a C, not an A. Calibrate expectations to the period: a *daily* window with two runs isn't "low activity" the way a *monthly* window with two runs would be.

## Step 4 — Render the card

Read `assets/pulse-template.html` and produce a filled copy. Keep its card-based aesthetic. The template already contains: a title (`QA Pulse`), highlighted **Project** and **Window** chips, a health pill, KPI tiles, an execution pass/fail bar, an Activity Stats grid (new cases, updated cases, new runs, new defects), an Active Users list with avatars, and a Watch-outs/Takeaways panel.

Adapt to the data and the period: set the **Window** chip to the resolved range and its cadence label (e.g. "Aug 1 – Aug 31 · monthly"), resize the pass/fail bar to the real ratio, add one Active-User row per person (initials avatar + name + role + what they did + a stat chip), and write takeaways that reflect *this* project over *this* period rather than boilerplate. Always keep the methodology footnote (window, pass-rate definition, source).

**Writing the file is this skill's only side effect, and it is the only one in this plugin.** Save as `quality-pulse-<CODE>-<YYYY-MM-DD>.html` in the current working directory, unless the user named a destination — then use theirs. Never write outside it, and if a file of that name already exists, say so and ask before overwriting.

How to hand it over depends on the client, so state the path either way rather than assuming a viewer exists: in a terminal client the path is the deliverable (say the file is ready and where it is); in a client that renders or attaches files, present it there as well. Keep the closing message short — the card speaks for itself.

## Step 5 — Offer to make it recurring

After delivering, offer in one line to regenerate the pulse on a cadence matching the chosen period (daily brief, Monday weekly, first-of-month). Only set that up if the user says yes, and only with a mechanism their client actually has — scheduling and live, self-refreshing views exist in some clients and not others. Never promise a recurring or auto-updating pulse you cannot actually wire up; offering a re-run when asked is always available.

## Honesty notes

- If the window has little or no activity (common on demo/idle projects, or on short daily windows), say so plainly and report the last activity date rather than padding the card. A sparse but truthful pulse is more useful than an inflated one.
- Grades and takeaways are judgment calls — frame them as such, calibrate them to the length of the period, and make the underlying numbers visible so the reader can disagree.
- Every number on the card is read-only: this skill only reads Qase and writes the
  local HTML file. It never creates or edits cases, defects, or runs.
