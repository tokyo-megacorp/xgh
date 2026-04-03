#!/usr/bin/env bash
# PostToolUse hook — capture local command events for xgh trigger engine
#
# Called by Claude Code after each tool use.
# Receives JSON on stdin: { tool_name, tool_input, tool_response }
#
# If any ~/.xgh/triggers/*.yaml has `source: local`, checks whether the
# command matches. Writes a local_command inbox item to ~/.xgh/inbox if so.

set -euo pipefail

# Cross-platform timeout wrapper (macOS lacks GNU timeout by default)
_run_timeout() { local secs=$1; shift; if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; else "$@"; fi; }

TRIGGER_DIR="${HOME}/.xgh/triggers"
INBOX_DIR="${HOME}/.xgh/inbox"

# Fast exit: no triggers dir = nothing to do
[ -d "$TRIGGER_DIR" ] || exit 0

# Fast exit: no local triggers = nothing to do
if ! grep -ql "source: local" "$TRIGGER_DIR"/*.yaml 2>/dev/null; then
  exit 0
fi

# Read hook JSON from stdin
HOOK_JSON=$(cat 2>/dev/null || echo "{}")
[ -n "$HOOK_JSON" ] || exit 0

# Only process Bash tool calls
TOOL_NAME=$(echo "$HOOK_JSON" | _run_timeout 10 python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")
[ "$TOOL_NAME" = "Bash" ] || exit 0

# Extract command and exit code
COMMAND=$(echo "$HOOK_JSON" | _run_timeout 10 python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" \
  2>/dev/null || echo "")
EXIT_CODE=$(echo "$HOOK_JSON" | _run_timeout 10 python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_response',{}).get('exit_code',0))" \
  2>/dev/null || echo "0")

[ -n "$COMMAND" ] || exit 0

# Check if any local trigger's command pattern matches
MATCHED=false
while IFS= read -r -d '' TRIGGER_FILE; do
  # Read command pattern from trigger YAML
  CMD_PATTERN=$(grep "^  command:" "$TRIGGER_FILE" 2>/dev/null | head -1 | sed 's/^[[:space:]]*command:[[:space:]]*//' | sed 's/^"//' | sed 's/"$//' || echo "")
  [ -n "$CMD_PATTERN" ] || continue

  # Check exit_code expectation (default: 0)
  EXPECTED_EXIT=$(grep "exit_code:" "$TRIGGER_FILE" 2>/dev/null | head -1 | awk '{print $2}' || echo "0")
  [ "$EXIT_CODE" = "$EXPECTED_EXIT" ] || continue

  # Match command against pattern
  if echo "$COMMAND" | grep -qE "$CMD_PATTERN" 2>/dev/null; then
    MATCHED=true
    break
  fi
done < <(find "$TRIGGER_DIR" -name "*.yaml" -not -name ".*" -print0 2>/dev/null)

[ "$MATCHED" = "true" ] || exit 0

# Write inbox item
mkdir -p "$INBOX_DIR"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
SAFE_CMD=$(echo "$COMMAND" | tr ' /()[]{}' '_' | head -c 40)
INBOX_FILE="$INBOX_DIR/${TIMESTAMP}_local_command_${SAFE_CMD}.md"

# Escape for YAML (handle quotes and special chars)
YAML_COMMAND=$(_run_timeout 10 python3 -c "import sys,json; print(json.dumps(sys.argv[1]))" "$COMMAND" 2>/dev/null || echo "\"$COMMAND\"")
YAML_TITLE=$(_run_timeout 10 python3 -c "import sys,json; print(json.dumps(sys.argv[1][:80]))" "$COMMAND" 2>/dev/null || echo "\"$COMMAND\"" | head -c 80)

cat > "$INBOX_FILE" << YAML
---
source_type: local_command
source: local
command: $YAML_COMMAND
exit_code: $EXIT_CODE
title: $YAML_TITLE
timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
urgency_score: 50
---

Local command executed successfully.
Command: $COMMAND
Exit code: $EXIT_CODE
YAML

exit 0
