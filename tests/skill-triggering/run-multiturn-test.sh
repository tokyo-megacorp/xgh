#!/usr/bin/env bash
# Multi-turn continuity test — verifies skill triggering after conversation context accumulation
#
# This reproduces the failure mode where Claude skips skill invocation after
# extended conversation. Tests xgh:briefing since it has natural-language triggers.
#
# Uses --session-id + --resume instead of --continue for deterministic session targeting.
# Cannot use --no-session-persistence or --bare here — turns 2-3 need to resume the session.
#
# Environment variables:
#   XGH_TEST_MODEL    — model to use (default: sonnet)
#   XGH_TEST_BUDGET   — max USD per invocation (default: 0.50)
#
# Usage: ./run-multiturn-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configurable via environment
MODEL="${XGH_TEST_MODEL:-sonnet}"
BUDGET="${XGH_TEST_BUDGET:-0.50}"

# Generate a unique session ID for this test run (deterministic targeting, not fragile --continue)
SESSION_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"

TIMESTAMP=$(date +%s)
OUTPUT_DIR="/tmp/xgh-skill-tests/${TIMESTAMP}/multiturn"
mkdir -p "$OUTPUT_DIR"

echo "=== xgh Multi-Turn Skill Continuity Test ==="
echo "Skill under test: xgh:briefing"
echo "Session ID: $SESSION_ID"
echo "Model: $MODEL"
echo "Output dir: $OUTPUT_DIR"
echo ""

# ── Turn 1: Start a routine conversation ────────────────────────────────────
TURN1_PROMPT="I just got in. Let me check some things. What's the status of the codebase?"
TURN1_LOG="$OUTPUT_DIR/turn1.json"

TURN1_CMD=(
    claude -p "$TURN1_PROMPT"
    --plugin-dir "$PLUGIN_DIR"
    --dangerously-skip-permissions
    --session-id "$SESSION_ID"
    --verbose
    --model "$MODEL"
    --max-budget-usd "$BUDGET"
    --output-format stream-json
)
echo ">>> Turn 1: Starting a routine work conversation..."
echo "\$ ${TURN1_CMD[*]}"
echo ""
"${TURN1_CMD[@]}" > "$TURN1_LOG" 2>&1 || true
echo "Turn 1 complete."

# ── Turn 2: Accumulate more context ────────────────────────────────────────
# NOTE: --resume targets the exact session ID from turn 1 (not "most recent").
# Runs must be sequential to avoid race conditions.
TURN2_PROMPT="Thanks. I also noticed some Slack messages piling up from last night. We had an incident."
TURN2_LOG="$OUTPUT_DIR/turn2.json"

TURN2_CMD=(
    claude -p "$TURN2_PROMPT"
    --resume "$SESSION_ID"
    --plugin-dir "$PLUGIN_DIR"
    --dangerously-skip-permissions
    --verbose
    --model "$MODEL"
    --max-budget-usd "$BUDGET"
    --output-format stream-json
)
echo ""
echo ">>> Turn 2: Accumulating more conversation context..."
echo "\$ ${TURN2_CMD[*]}"
echo ""
"${TURN2_CMD[@]}" > "$TURN2_LOG" 2>&1 || true
echo "Turn 2 complete."

# ── Turn 3: THE TEST — natural language trigger after context accumulation ──
TURN3_PROMPT="Ok, enough context. What needs my attention right now? Give me a full briefing."
TURN3_LOG="$OUTPUT_DIR/turn3.json"

TURN3_CMD=(
    claude -p "$TURN3_PROMPT"
    --resume "$SESSION_ID"
    --plugin-dir "$PLUGIN_DIR"
    --dangerously-skip-permissions
    --verbose
    --model "$MODEL"
    --max-budget-usd "$BUDGET"
    --output-format stream-json
)
echo ""
echo ">>> Turn 3: Triggering xgh:briefing after context accumulation..."
echo "\$ ${TURN3_CMD[*]}"
echo ""
"${TURN3_CMD[@]}" > "$TURN3_LOG" 2>&1 || true
echo "Turn 3 complete."

# ── Results ─────────────────────────────────────────────────────────────────
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
echo "Session: $SESSION_ID"
echo "Logs: $OUTPUT_DIR"

if [ "$TRIGGERED" = "true" ]; then
    exit 0
else
    exit 1
fi
