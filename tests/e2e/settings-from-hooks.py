#!/usr/bin/env python3
"""Render the plugin's real hooks/hooks.json into a Claude Code settings file.

wire-check.sh used to restate the hook registrations inline. That is what let a
registration bug through once: the test kept passing while hooks.json itself was
wrong, because the copy in the test and the real file had drifted apart. Reading
the real file means the end-to-end check fails when the registration does.
"""
import io
import json
import sys

repo, out = sys.argv[1], sys.argv[2]
hooks = json.load(io.open(repo + "/hooks/hooks.json", encoding="utf-8"))["hooks"]


def resolve(node):
    """Substitute ${CLAUDE_PLUGIN_ROOT}, which only the plugin loader expands."""
    if isinstance(node, dict):
        return {k: resolve(v) for k, v in node.items()}
    if isinstance(node, list):
        return [resolve(v) for v in node]
    if isinstance(node, str):
        return node.replace("${CLAUDE_PLUGIN_ROOT}", repo)
    return node


settings = {
    "permissions": {"allow": ["mcp__qase__qase_qql", "Skill"]},
    "hooks": resolve(hooks),
}
io.open(out, "w", encoding="utf-8").write(json.dumps(settings, indent=2) + "\n")
