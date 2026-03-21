#!/usr/bin/env bash
# Multi-turn continuity test — verifies skill triggering after conversation context accumulation
#
# This reproduces the failure mode where Claude skips skill invocation after
# extended conversation. Tests xgh:briefing since it has natural-language triggers.
#
# Usage: ./run-multiturn-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

TIMESTAMP=$(date +%s)
OUTPUT_DIR="/tmp/xgh-skill-tests/${TIMESTAMP}/multiturn"
mkdir -p "$OUTPUT_DIR"

echo "=== xgh Multi-Turn Skill Continuity Test ==="
echo "Skill under test: xgh:briefing"
echo "Output dir: $OUTPUT_DIR"
echo ""

# Turn 1: Start a routine conversation
echo ">>> Turn 1: Starting a routine work conversation..."
TURN1_LOG="$OUTPUT_DIR/turn1.json"
claude -p "I just got in. Let me check some things. What's the status of the codebase?" \
    --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    --verbose \
    --output-format stream-json \
    > "$TURN1_LOG" 2>&1 || true
echo "Turn 1 complete."

# Turn 2: Continue with more context
# NOTE: --continue resumes the most recent Claude Code session on this machine.
# Runs must be sequential (not parallel) to avoid attaching to the wrong session.
echo ""
echo ">>> Turn 2: Accumulating more conversation context..."
TURN2_LOG="$OUTPUT_DIR/turn2.json"
claude -p "Thanks. I also noticed some Slack messages piling up from last night. We had an incident." \
    --continue \
    --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    --verbose \
    --output-format stream-json \
    > "$TURN2_LOG" 2>&1 || true
echo "Turn 2 complete."

# Turn 3: THE TEST — natural language trigger after context accumulation
echo ""
echo ">>> Turn 3: Triggering xgh:briefing after context accumulation..."
TURN3_LOG="$OUTPUT_DIR/turn3.json"
claude -p "Ok, enough context. What needs my attention right now? Give me a full briefing." \
    --continue \
    --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    --verbose \
    --output-format stream-json \
    > "$TURN3_LOG" 2>&1 || true
echo "Turn 3 complete."

echo ""
echo "=== Results ==="

SKILL_PATTERN='"skill":"([^"]*:)?briefing"'
if grep -q '"name":"Skill"' "$TURN3_LOG" && grep -qE "$SKILL_PATTERN" "$TURN3_LOG"; then
    echo "✅ PASS: xgh:briefing triggered in Turn 3 (after context accumulation)"
    TRIGGERED=true
else
    echo "❌ FAIL: xgh:briefing NOT triggered in Turn 3"
    echo "  Skills triggered in Turn 3:"
    SKILLS=$(grep -o '"skill":"[^"]*"' "$TURN3_LOG" 2>/dev/null || true)
    if [ -n "$SKILLS" ]; then echo "$SKILLS" | sort -u; else echo "  (none)"; fi
    TRIGGERED=false
fi

echo ""
echo "Logs: $OUTPUT_DIR"

if [ "$TRIGGERED" = "true" ]; then
    exit 0
else
    exit 1
fi
