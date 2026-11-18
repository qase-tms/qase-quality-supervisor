#!/bin/bash
#
# Builds the OpenAI plugin directory ZIP and checks it against the rules the
# directory enforces at upload and at submission
# (developers.openai.com/plugins/deploy/submission-errors). A rule broken here
# would otherwise surface only after a manual upload to the portal.
#
# Where the docs give two limits, the stricter submission limit is checked:
# the description at 1,024 characters, the listing fields at their final sizes.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if ! zip_path="$(bash "$REPO_ROOT/scripts/build-openai-package.sh" "$work/out")"; then
  echo "FAIL: build-openai-package.sh did not build the package" >&2
  exit 1
fi

/usr/bin/python3 - "$zip_path" "$REPO_ROOT" <<'EOF'
import json, re, struct, sys, zipfile

zip_path, repo_root = sys.argv[1], sys.argv[2]
failures = 0

def check(ok, message):
    global failures
    if ok:
        print(f"PASS: {message}")
    else:
        print(f"FAIL: {message}", file=sys.stderr)
        failures += 1

archive = zipfile.ZipFile(zip_path)
names = [n for n in archive.namelist() if not n.endswith("/")]

tops = {n.split("/", 1)[0] for n in archive.namelist()}
check(tops == {"quality-supervisor"}, "the archive holds one plugin root and nothing beside it")
files = {n.split("/", 1)[1] for n in names}

for required in ("plugin.json", "mcp.json", "LICENSE", "assets/logo.png"):
    check(required in files, f"the package contains {required}")

# Hooks and app references make a package unsubmittable; the Claude Code and
# Codex manifests carry hooks, so none of them may leak in.
for banned in ("hooks/", ".claude-plugin/", ".codex-plugin/", ".app.json", ".mcp.json"):
    check(not any(f.startswith(banned) or f == banned for f in files),
          f"the package leaves out {banned}")

root = "quality-supervisor/"
manifest = json.loads(archive.read(root + "plugin.json"))
mcp = json.loads(archive.read(root + "mcp.json"))

claude_version = json.load(open(f"{repo_root}/.claude-plugin/plugin.json"))["version"]
check(manifest.get("version") == claude_version,
      "the package version matches .claude-plugin/plugin.json")
check(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", manifest.get("name", "")) is not None,
      "the plugin name has the allowed form")
check(0 < len(manifest.get("description", "")) <= 1024, "the description fits 1,024 characters")

openai = manifest.get("extensions", {}).get("com.openai", {})
ui = openai.get("interface", {})

limits = {"displayName": 30, "shortDescription": 30, "longDescription": 4000, "developerName": 80}
for field, limit in limits.items():
    value = ui.get(field, "")
    check(0 < len(value) <= limit, f"interface.{field} is set and fits {limit} characters")
check("\n" not in ui.get("shortDescription", ""), "interface.shortDescription is one line")
check(not re.search(r"\b(MCP|Plugin)\b", ui.get("displayName", "")),
      "the display name does not append MCP or Plugin")

categories = {"Productivity", "Creativity", "Developer Tools", "Business & Operations",
              "Data & Analytics", "Communication", "Education & Research", "Security",
              "Finance", "Healthcare", "Travel", "Entertainment", "Other"}
check(ui.get("category") in categories, "interface.category is a known category")

capabilities = ui.get("capabilities", [])
check(len(capabilities) <= 20 and all(0 < len(c) <= 120 for c in capabilities),
      "interface.capabilities are within limits")

for field in ("websiteURL", "supportURL", "privacyPolicyURL", "termsOfServiceURL"):
    url = ui.get(field, "")
    check(url.startswith("https://") and "@" not in url and len(url) <= 1024,
          f"interface.{field} is an HTTPS URL without credentials")

prompts = ui.get("defaultPrompt", [])
prompts = [prompts] if isinstance(prompts, str) else prompts
check(len(prompts) <= 3 and len(set(prompts)) == len(prompts), "at most three distinct default prompts")
check(all(0 < len(p) <= 128 and "\n" not in p and "@" not in p for p in prompts),
      "default prompts are single lines within 128 characters, without @mentions")

def luminance(hex_color):
    channels = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    channels = [c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]

color = ui.get("brandColor", "")
if color:
    ok = re.fullmatch(r"#[0-9A-Fa-f]{6}", color) is not None
    check(ok and 1.05 / (luminance(color) + 0.05) >= 2, "brandColor contrasts 2:1 against white")

def png_size(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", data[16:24])

for field in ("logo", "composerIcon"):
    path = ui.get(field, "")
    entry = root + path.removeprefix("./")
    present = path.startswith("./") and entry in archive.namelist()
    check(present, f"interface.{field} points at a file in the package")
    if present:
        size = png_size(archive.read(entry))
        check(size is not None and size[0] == size[1] and 48 <= size[0] <= 4096,
              f"interface.{field} is a square PNG between 48 and 4096 pixels")

cases = openai.get("review", {}).get("test_cases", {})
positive, negative = cases.get("positive", []), cases.get("negative", [])
check(len(positive) == 5, "exactly five positive test cases")
check(len(negative) == 3, "exactly three negative test cases")
check(all(all(c.get(k) for k in ("description", "prompt", "tools_triggered", "expected_behavior"))
          for c in positive), "every positive case has description, prompt, tools and expected behavior")
check(all(c.get("description") and c.get("prompt") for c in negative),
      "every negative case has a description and a prompt")
check(bool(openai.get("publication", {}).get("release_notes")), "release notes are set")

banned_review_keys = {"test_credentials", "reviewer_instructions", "clientSecret"}
check(not banned_review_keys & set(json.dumps(manifest).replace('"', " ").split()),
      "no credentials or reviewer instructions in the manifest")

servers = mcp.get("mcpServers", {})
check(len(servers) == 1, "exactly one MCP server")
for name, server in servers.items():
    check(server.get("type") == "streamable-http" and server.get("url", "").startswith("https://"),
          f"MCP server {name} is remote over HTTPS")
    check(not server.get("headers"), f"MCP server {name} sends no static headers")
    auth = server.get("extensions", {}).get("com.openai", {}).get("auth", {})
    check(auth.get("type") == "oauth" and auth.get("client", {}).get("mode") == "dcr",
          f"MCP server {name} signs in with OAuth through dynamic client registration")

skill_dirs = {f.split("/")[1] for f in files if f.startswith("skills/") and f.count("/") >= 2}
check(len(skill_dirs) > 0, "the package carries at least one skill")
for skill in sorted(skill_dirs):
    check(f"skills/{skill}/SKILL.md" in files, f"skills/{skill} has a SKILL.md")

# Skills link to shared files relative to themselves; a link that leaves the
# package would point the model at nothing.
for name in names:
    if not name.endswith(".md") or "/skills/" not in name:
        continue
    text = archive.read(name).decode("utf-8")
    base = name.rsplit("/", 1)[0]
    links = re.findall(r"\]\((\.\.?/[^)#\s]+)\)", text) + re.findall(r"`(\.\.?/[^`\s]+)`", text)
    for link in sorted(set(links)):
        parts = []
        for part in f"{base}/{link}".split("/"):
            if part == "..":
                parts.pop() if parts else None
            elif part and part != ".":
                parts.append(part)
        check("/".join(parts) in archive.namelist(), f"{name.removeprefix(root)} links to {link}, which is packaged")

sys.exit(1 if failures else 0)
EOF
status=$?

if [ "$status" -ne 0 ]; then
  echo "test-openai-package: FAILED" >&2
  exit 1
fi
echo "test-openai-package: all checks passed"
