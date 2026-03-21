#!/usr/bin/env bash
# Test agent dispatching — verifies that a prompt causes Claude to dispatch the named agent
# Usage: ./run-agent-test.sh <agent-name> <prompt-file>
#
# Tests whether Claude dispatches an agent based on a natural-language prompt.
# Checks for the Agent tool invocation with matching subagent_type in stream-json output.
#
# Examples:
#   ./run-agent-test.sh xgh:pipeline-doctor prompts/agent-pipeline-doctor.txt
#   ./run-agent-test.sh xgh:pr-reviewer     prompts/agent-pr-reviewer.txt

set -euo pipefail

AGENT_NAME="$1"
PROMPT_FILE="$2"

if [ -z "$AGENT_NAME" ] || [ -z "$PROMPT_FILE" ]; then
    echo "Usage: $0 <agent-name> <prompt-file>"
    echo "Example: $0 xgh:pipeline-doctor prompts/agent-pipeline-doctor.txt"
    exit 1
fi

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

TIMESTAMP=$(date +%s)
OUTPUT_DIR="/tmp/xgh-agent-tests/${TIMESTAMP}/${AGENT_NAME//:/--}"
mkdir -p "$OUTPUT_DIR"

[ -f "$PROMPT_FILE" ] || { echo "Error: prompt file not found: $PROMPT_FILE"; exit 1; }
PROMPT=$(cat "$PROMPT_FILE")

echo "=== xgh Agent Dispatch Test ==="
echo "Agent:       $AGENT_NAME"
echo "Prompt file: $PROMPT_FILE"
echo "Plugin dir:  $PLUGIN_DIR"
echo ""

cp "$PROMPT_FILE" "$OUTPUT_DIR/prompt.txt"

LOG_FILE="$OUTPUT_DIR/claude-output.json"

echo "Running claude -p ..."
# --verbose is required for --output-format stream-json with -p
# Note: `timeout` is not available on macOS by default; claude has its own session timeout
claude -p "$PROMPT" \
    --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    --verbose \
    --output-format stream-json \
    > "$LOG_FILE" 2>&1 || true

echo ""
echo "=== Results ==="

# Extract the agent base name (xgh:pipeline-doctor → pipeline-doctor) for flexible matching
# Matches both "xgh:pipeline-doctor" and bare "pipeline-doctor" in subagent_type
AGENT_BASE="${AGENT_NAME##*:}"
AGENT_PATTERN='"subagent_type":"([^"]*:)?'"${AGENT_BASE}"'"'

if grep -q '"name":"Agent"' "$LOG_FILE" && grep -qE "$AGENT_PATTERN" "$LOG_FILE"; then
    echo "✅ PASS: Agent '$AGENT_NAME' was dispatched"
    TRIGGERED=true
else
    echo "❌ FAIL: Agent '$AGENT_NAME' was NOT dispatched"
    TRIGGERED=false
fi

# Show all agents that were dispatched
echo ""
echo "Agents dispatched:"
AGENTS=$(grep -o '"subagent_type":"[^"]*"' "$LOG_FILE" 2>/dev/null || true)
if [ -n "$AGENTS" ]; then echo "$AGENTS" | sort -u; else echo "  (none)"; fi

# Show all skills that were triggered (agents may invoke skills too)
echo ""
echo "Skills triggered:"
SKILLS=$(grep -o '"skill":"[^"]*"' "$LOG_FILE" 2>/dev/null || true)
if [ -n "$SKILLS" ]; then echo "$SKILLS" | sort -u; else echo "  (none)"; fi

# Show first assistant response (truncated)
echo ""
echo "First assistant response (truncated to 300 chars):"
grep '"type":"assistant"' "$LOG_FILE" 2>/dev/null | head -1 \
    | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); content=d.get('message',{}).get('content',[]); print(content[0].get('text','')[:300] if content else '')" \
    2>/dev/null || echo "  (could not extract)"

echo ""
echo "Full log: $LOG_FILE"

if [ "$TRIGGERED" = "true" ]; then
    exit 0
else
    exit 1
fi
