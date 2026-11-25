#!/bin/bash
#
# Holds the Cursor plugin to the marketplace's submission checklist and to the
# guard it must carry. Cursor reads hooks/hooks.json by default, which is Claude
# Code's file, so the manifest has to point it at the Cursor one.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."

/usr/bin/python3 - "$ROOT" <<'EOF'
import io, json, os, re, subprocess, sys

root = sys.argv[1]
failures = 0

def check(ok, msg):
    global failures
    print(("PASS: " if ok else "FAIL: ") + msg, file=sys.stdout if ok else sys.stderr)
    if not ok:
        failures += 1

def load(rel):
    return json.load(io.open(os.path.join(root, rel), encoding="utf-8"))

m = load(".cursor-plugin/plugin.json")
check(bool(re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", m.get("name", ""))),
      "name is lowercase kebab-case")
check(bool(m.get("description")), "description is set")
check(bool(re.fullmatch(r"\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?", m.get("version", ""))),
      "version is semver")

# The checklist allows relative paths only, and a missing file fails silently.
for field in ("logo", "mcpServers", "hooks"):
    p = m.get(field, "")
    ok = isinstance(p, str) and p and not os.path.isabs(p) and ".." not in p.split("/")
    check(ok and os.path.isfile(os.path.join(root, p)), f"{field} is a relative path to an existing file")
check(m.get("hooks") != "./hooks/hooks.json", "hooks does not point at Claude Code's hooks.json")

skills = os.path.join(root, "skills")
check(all(os.path.isfile(os.path.join(skills, d, "SKILL.md")) for d in os.listdir(skills)
          if os.path.isdir(os.path.join(skills, d))), "every skill folder has a SKILL.md")

servers = list(load(m["mcpServers"])["mcpServers"])
check(servers == ["qase"], f"the MCP config declares only the qase server (got {servers})")

h = load(m["hooks"])
check(h.get("version") == 1, "hooks file declares version 1")
guards = h.get("hooks", {}).get("preToolUse", [])
check(len(guards) == 1, "one preToolUse guard")
g = guards[0] if guards else {}
# Cursor fails open on a crash or timeout unless told otherwise.
check(g.get("failClosed") is True, "the guard fails closed")

deletes = ["case", "suite", "run", "result", "defect", "plan", "milestone", "environment",
           "shared_step", "project", "custom_field", "attachment", "review"]
keep = ["qase_case_upsert", "qase_api", "qql_search", "qase_get", "delete_branch", "delete_file"]
# Undocumented whether Cursor searches or full-matches, and whether the name
# carries its MCP: prefix, so the pattern has to work every way.
pat = re.compile(g.get("matcher", "^$"))
def hits(name):
    return [bool(f(pat, s)) for s in (name, "MCP:" + name) for f in (re.search, re.fullmatch)]
check(all(all(hits(f"qase_{d}_delete")) for d in deletes), "the matcher catches every qase_*_delete tool")
check(not any(any(hits(n)) for n in keep), "the matcher leaves reads, writes and other servers alone")

out = subprocess.run(["bash", "-c", g.get("command", "false")], input="{}",
                     capture_output=True, text=True)
try:
    answer = json.loads(out.stdout)
except ValueError:
    answer = {}
check(out.returncode == 0 and answer.get("permission") == "deny", "the guard answers deny under bash")

# On Windows the desktop app runs hook commands through PowerShell.
pwsh = next((p for p in ("pwsh", "powershell") if subprocess.run(["which", p], capture_output=True).returncode == 0), None)
if pwsh:
    out = subprocess.run([pwsh, "-NoProfile", "-Command", g.get("command", "exit 1")],
                         input="{}", capture_output=True, text=True)
    try:
        answer = json.loads(out.stdout)
    except ValueError:
        answer = {}
    check(out.returncode == 0 and answer.get("permission") == "deny", "the guard answers deny under PowerShell")
else:
    print("SKIP: no PowerShell to run the guard under")

sys.exit(1 if failures else 0)
EOF
status=$?
[ "$status" -eq 0 ] && echo "Cursor plugin checks passed."
exit "$status"
