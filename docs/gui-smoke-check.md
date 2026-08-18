# GUI smoke check — 10 minutes

Everything about this plugin has been verified through the `claude` CLI and in CI.
Dogfooders will use Claude Desktop and Cowork instead, and three things behave
differently there: installation, the OAuth flow, and how commands are typed. This
walks those three, plus the one guarantee worth confirming by hand.

Run it once per client before inviting anyone. If step 2 fails, stop and report —
everything after it depends on a working connection, and dogfooders hitting the
same wall will spend their time on setup instead of the product.

Record the result in the table at the bottom.

---

## 1. Install — 2 min

```
/plugin marketplace add qase-tms/qase-quality-supervisor
/plugin install quality-supervisor@quality-supervisor
```

Restart the client so the skills load, then:

```
/plugin
```

**Expect:** `quality-supervisor` listed and enabled, with **5 skills, 1 agent, 1
PreToolUse hook** — the CLI counts the `quality-report` command under `Skills`, so
four skills plus a command prints as five. The five names are
`analyzing-test-flakiness`, `assessing-release-readiness`, `finding-coverage-gaps`,
`quality-report`, `triaging-test-failures`.

**Note if:** the marketplace add fails, the install needs different syntax in this
client, or the component counts differ from 5/1/1. A GUI client may well group
them differently from the CLI — if it shows 4 skills and 1 command separately,
that is the same inventory presented another way, not a finding. Record which
shape you saw.

> In Cowork, installing the packaged `.plugin` file directly may be the only route.
> If so, record which path worked — the README currently offers both without
> knowing which one Cowork actually accepts.

## 2. Authorise — 2 min, and the step most likely to break

Type a question that needs Qase. Substitute a project code you can read:

```
Which tests are flaky in WEB?
```

**Expect:** the client opens a browser for the Qase OAuth flow on first use. You
authorise with your normal Qase login. No token anywhere.

**This is the step to watch.** The CLI cannot complete this flow at all in
headless mode, so every automated check to date has used a token-based server
instead. That makes this path — hosted OAuth in a GUI client — genuinely
unverified rather than merely untested-in-this-client.

**Note if:**
- no browser opens, or the flow starts but doesn't return;
- it succeeds but the next question re-prompts (token not persisted);
- you get a plan error. Hosted needs **Enterprise**; QQL needs **Business or
  Enterprise**. On Business, switch to the local server per QUICKSTART step 2b and
  note that you did — the rest of this check is still valid.

## 3. One real report — 4 min

```
/quality-supervisor:quality-report WEB
```

**Expect:** a report with these sections — Coverage gaps, Flakiness, Latest run
triage, Release readiness (or "skipped — no scope supplied"), **Data confidence**,
Recommended actions. Roughly 5 minutes and about $2.80 on a large model.

**Note if:**
- the bare `/quality-report` is what this client autocompletes to — it returns
  "Unknown command", and if the client suggests it, that's worth knowing;
- **Data confidence is missing.** That section is the difference between this and a
  tool that always prints a confident number; its absence is a real defect, not
  cosmetic;
- any figure appears without its denominator;
- it reports a GO while also reporting untested scope.

## 4. Confirm the guard by hand — 2 min

The delete guard is tested end to end in CI, but only through the CLI. Confirm the
hook loads in this client:

```
Delete the test case with id <some id you can afford to lose> in WEB
```

**Expect:** refusal, saying deletion is disabled — and the case still there
afterwards. Check in the Qase UI, not just by asking.

**Note if:** it deletes, or claims it deleted, or the refusal comes from the model
being cautious rather than from the guard. If the wording sounds like "I'd rather
not" instead of naming a block, the hook may not be loading in this client — which
would be the most serious finding in this whole check.

## 5. Two questions in your own words — 1 min

```
What isn't tested in WEB?
Why did last night's WEB run fail?
```

**Expect:** the matching skill fires for at least one of them. Routing lands about
90% of the time on large models and 58% on Haiku, so one miss out of two is within
normal — it is not a finding unless *neither* fires, or the wrong one does.

**Note if:** the wrong skill fires. `triaging-test-failures` and
`analyzing-test-flakiness` prescribe opposite actions — quarantine the test versus
fix the product — so confusing them inverts the advice, and that is the one routing
failure that matters.

---

## Result

| Step | Claude Desktop | Cowork | Notes |
|---|---|---|---|
| 1 Install | | | |
| 2 OAuth | | | |
| 3 Report | | | |
| 4 Guard | | | |
| 5 Routing | | | |

Client and version:
Qase plan:
Model:

Anything unexpected → [misfire report](https://github.com/qase-tms/qase-quality-supervisor/issues/new?template=misfire.yml),
or just paste the notes back to me.

## What a pass here means

Steps 1–4 green in a client means dogfooders can install, connect, get a report,
and cannot destroy data through it. That is the bar for inviting people.

It does **not** mean the analysis is right on their projects — that is what the two
weeks of dogfooding are for, and the misfire form is how those findings get back.
