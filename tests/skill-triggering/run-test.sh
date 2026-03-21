#!/usr/bin/env bash
# Test skill triggering — verifies that a prompt causes Claude to invoke the named skill
# Usage: ./run-test.sh <skill-name> <prompt-file>
#
# Tests whether Claude triggers a skill based on a prompt.
# Supports both natural-language prompts and explicit /command prompts.
#
# Examples:
#   ./run-test.sh xgh:briefing prompts/briefing.txt
#   ./run-test.sh xgh:track   prompts/track.txt

set -euo pipefail

SKILL_NAME="$1"
PROMPT_FILE="$2"

if [ -z "$SKILL_NAME" ] || [ -z "$PROMPT_FILE" ]; then
    echo "Usage: $0 <skill-name> <prompt-file>"
    echo "Example: $0 xgh:briefing prompts/briefing.txt"
    exit 1
fi

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

TIMESTAMP=$(date +%s)
OUTPUT_DIR="/tmp/xgh-skill-tests/${TIMESTAMP}/${SKILL_NAME//:/--}"
mkdir -p "$OUTPUT_DIR"

[ -f "$PROMPT_FILE" ] || { echo "Error: prompt file not found: $PROMPT_FILE"; exit 1; }
PROMPT=$(cat "$PROMPT_FILE")

echo "=== xgh Skill Triggering Test ==="
echo "Skill:       $SKILL_NAME"
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

# Extract just the skill base name (xgh:briefing → briefing) for flexible matching
# Matches both "xgh:briefing" and bare "briefing" in case of namespace variations
SKILL_BASE="${SKILL_NAME##*:}"
SKILL_PATTERN='"skill":"([^"]*:)?'"${SKILL_BASE}"'"'

if grep -q '"name":"Skill"' "$LOG_FILE" && grep -qE "$SKILL_PATTERN" "$LOG_FILE"; then
    echo "✅ PASS: Skill '$SKILL_NAME' was triggered"
    TRIGGERED=true
else
    echo "❌ FAIL: Skill '$SKILL_NAME' was NOT triggered"
    TRIGGERED=false
fi

# Show all skills that were triggered
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
