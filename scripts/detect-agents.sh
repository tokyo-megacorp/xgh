#!/usr/bin/env bash
set -euo pipefail

# detect-agents.sh — Detects secondary AI coding tools installed in the current project/environment
#
# Detection logic:
#   - Binary tools (codex, gemini, opencode, aider): checked via `command -v`
#   - Directory-based tools (cursor, continue): checked via directory presence in cwd
#
# Output: JSON array of detected agent names, e.g. ["codex","gemini","cursor"]
#
# Exit codes:
#   0 — success (even if no agents found — empty array is valid)
#   1 — unexpected error

detected=()

# Binary-based tools
for bin in codex gemini opencode aider; do
  if command -v "$bin" >/dev/null 2>&1; then
    detected+=("\"$bin\"")
  fi
done

# Directory-based tools (checked relative to cwd)
if [ -d ".cursor" ]; then
  detected+=("\"cursor\"")
fi

if [ -d ".continue" ]; then
  detected+=("\"continue\"")
fi

# Output JSON array
if [ "${#detected[@]}" -eq 0 ]; then
  echo "[]"
else
  # Join array elements with commas
  joined=""
  for item in "${detected[@]}"; do
    if [ -z "$joined" ]; then
      joined="$item"
    else
      joined="$joined,$item"
    fi
  done
  echo "[$joined]"
fi
