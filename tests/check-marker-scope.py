#!/usr/bin/env python3
"""Assert the Codex attribution hook approves read-only Qase tools and no others.

The hook that attaches the usage marker in Codex must also approve the call —
Codex discards rewritten arguments otherwise. That approval is the whole risk of
the design, so its blast radius is checked against the server's full tool list
rather than a sample: every mutating tool must fall outside the matcher, and every
read-only tool must fall inside it.
"""
import io
import json
import re
import sys

MUTATING = """
qase_case_upsert qase_case_bulk_create qase_case_delete qase_suite_upsert
qase_suite_delete qase_run_upsert qase_run_delete qase_run_complete
qase_plan_upsert qase_plan_delete qase_milestone_upsert qase_milestone_delete
qase_defect_upsert qase_defect_delete qase_result_record qase_result_delete
qase_review_create qase_review_bulk_create qase_review_update qase_review_delete
qase_shared_step_upsert qase_shared_step_delete qase_api qase_environment_upsert
qase_environment_delete qase_attachment_upload qase_attachment_delete
qase_project_create qase_project_delete qase_triage_defect qase_ci_report
qase_custom_field_upsert qase_custom_field_delete qase_external_issue_link
qase_regression_run qase_discover_tools
""".split()

READ_ONLY = ["qase_get", "qase_project_context", "qql_search", "qql_help"]

root = sys.argv[1]
hooks = json.load(io.open(root + "/hooks/hooks.codex.json", encoding="utf-8"))["hooks"]

matcher = None
for group in hooks.get("PreToolUse", []):
    if any("mark-run" in h["command"] for h in group["hooks"]):
        m = group.get("matcher", "")
        if m.startswith("mcp__qase__"):
            matcher = m
            break

if matcher is None:
    print("FAIL: hooks.codex.json has no Qase matcher for the attribution hook")
    sys.exit(1)

leaked = [t for t in MUTATING if re.fullmatch(matcher, "mcp__qase__" + t)]
missed = [t for t in READ_ONLY if not re.fullmatch(matcher, "mcp__qase__" + t)]

failed = False
if leaked:
    print("FAIL: the attribution hook would approve mutating tools: " + " ".join(leaked))
    failed = True
else:
    print("PASS: the attribution hook approves no mutating tool")

if missed:
    print("FAIL: read-only tools left unattributed: " + " ".join(missed))
    failed = True
else:
    print("PASS: every read-only tool is attributed")

sys.exit(1 if failed else 0)
