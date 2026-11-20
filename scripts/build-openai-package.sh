#!/bin/bash
#
# Builds the ZIP submitted to the OpenAI plugin directory (ChatGPT and Codex).
#
# The directory takes the portable Agent Plugins layout, with plugin.json and
# mcp.json at the plugin root, and rejects packages that carry lifecycle hooks.
# So the package is assembled from openai/ plus the skills, rather than zipped
# from the repository: the Claude Code and Codex installs keep their hooks.
#
# Usage: build-openai-package.sh [out-dir]   (defaults to dist/)
# Prints the path of the ZIP it wrote.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/dist}"

for cmd in zip sed; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "FAIL: required command '$cmd' not found on PATH." >&2
    exit 1
  fi
done

cd "$REPO_ROOT"

version="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' openai/plugin.json | head -1)"
if [ -z "$version" ]; then
  echo "FAIL: could not read \"version\" from openai/plugin.json." >&2
  exit 1
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

# One top-level directory and nothing beside it: the directory accepts a plugin
# root either at the archive root or in a single folder with no sibling files.
root="$stage/quality-supervisor"
mkdir -p "$root/assets"

cp openai/plugin.json openai/mcp.json LICENSE "$root/"
cp assets/logo.png "$root/assets/"
cp -R skills "$root/skills"
# Skills link to ../../references/qql.md, so the shared references travel too.
cp -R references "$root/references"
find "$root" -name '.DS_Store' -delete

mkdir -p "$OUT_DIR"
zip_path="$(cd "$OUT_DIR" && pwd)/quality-supervisor-openai-${version}.zip"
rm -f "$zip_path"
(cd "$stage" && zip -qrX "$zip_path" quality-supervisor)

echo "$zip_path"
