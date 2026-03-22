#!/usr/bin/env bash
# Run all xgh skill triggering tests (pure NL prompts)
# Usage: ./run-all.sh
#
# NOTE: This is an opt-in test suite — it invokes claude -p and costs API tokens.
# Do NOT call from tests/test-config.sh.
# Run manually when editing skill trigger descriptions.
#
# For agent dispatch tests, see tests/agent-dispatch/run-all.sh.
#
# Environment variables:
#   XGH_TEST_MODEL    — model to use (default: sonnet)
#   XGH_TEST_BUDGET   — max USD per test invocation (default: 0.50)
#   XGH_TEST_LOG_DIR  — persistent log directory (default: /tmp/xgh-test-logs)
#
# Cost estimate: ~36 prompts × 1 turn ≈ ~$1.80 per run (sonnet).
#
# Logs are saved to $XGH_TEST_LOG_DIR (default /tmp/xgh-test-logs):
#   summary.log          — one-line-per-test results
#   skill-xgh--NAME--N/  — per-variant logs (claude-output.json, prompt.txt, result.txt)
#
# Examples:
#   ./run-all.sh                         # run all skill tests (auto-discovered)
#   XGH_TEST_MODEL=haiku ./run-all.sh    # cheaper run with haiku

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="$SCRIPT_DIR/prompts"

export XGH_TEST_LOG_DIR="${XGH_TEST_LOG_DIR:-/tmp/xgh-test-logs}"
mkdir -p "$XGH_TEST_LOG_DIR"
SUMMARY_LOG="$XGH_TEST_LOG_DIR/summary.log"

# ── Auto-discover all prompt files ──────────────────────────────────────────
# Derive skill name from filename: strip numeric suffix (ask-2 → ask, ask → ask)
# then prefix with xgh:
SKILL_TESTS=()
shopt -s nullglob
for f in "$PROMPTS_DIR"/*.txt; do
    basename_no_ext="${f##*/}"
    basename_no_ext="${basename_no_ext%.txt}"
    # Strip only a purely numeric suffix (-1, -2, -99) — not alphanumeric like -2fa
    skill_base="$(echo "$basename_no_ext" | sed 's/-[0-9][0-9]*$//')"
    SKILL_TESTS+=("xgh:${skill_base}:$(basename "$f")")
done

echo "=== xgh Skill Triggering Tests ==="
echo "Plugin dir: $(cd "$SCRIPT_DIR/../.." && pwd)"
echo "Model:  ${XGH_TEST_MODEL:-sonnet}"
echo "Logs:   $XGH_TEST_LOG_DIR"
echo ""

echo "# xgh skill triggering test results — $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SUMMARY_LOG"
echo "# model=${XGH_TEST_MODEL:-sonnet}" >> "$SUMMARY_LOG"
echo "" >> "$SUMMARY_LOG"

PASSED=0
FAILED=0
RESULTS=()

for entry in "${SKILL_TESTS[@]}"; do
    SKILL="${entry%%:*}:$(echo "$entry" | cut -d: -f2)"
    PROMPT_FILE="${entry##*:}"
    PROMPT_SLUG="${PROMPT_FILE%.txt}"
    FULL_PROMPT="$PROMPTS_DIR/$PROMPT_FILE"

    if [ ! -f "$FULL_PROMPT" ]; then
        echo "⚠️  SKIP: No prompt file for $SKILL ($FULL_PROMPT)"
        echo "SKIP [skill] $SKILL ($PROMPT_SLUG) — missing prompt" >> "$SUMMARY_LOG"
        continue
    fi

    echo "--- Testing: $SKILL ($PROMPT_SLUG) ---"

    # Use per-variant log dir so variants don't overwrite each other
    VARIANT_LOG_DIR="${XGH_TEST_LOG_DIR}/skill-${SKILL//:/--}--${PROMPT_SLUG}"
    if XGH_TEST_LOG_DIR="$VARIANT_LOG_DIR" "$SCRIPT_DIR/run-test.sh" "$SKILL" "$FULL_PROMPT"; then
        PASSED=$((PASSED + 1))
        RESULTS+=("✅ $SKILL ($PROMPT_SLUG)")
        echo "PASS [skill] $SKILL ($PROMPT_SLUG)" >> "$SUMMARY_LOG"
    else
        FAILED=$((FAILED + 1))
        RESULTS+=("❌ $SKILL ($PROMPT_SLUG)")
        echo "FAIL [skill] $SKILL ($PROMPT_SLUG)" >> "$SUMMARY_LOG"
    fi

    echo ""
done

echo "=== Summary ==="
for result in "${RESULTS[@]}"; do
    echo "  $result"
done
echo ""
echo "Passed: $PASSED / $((PASSED + FAILED))"
echo "Logs:   $XGH_TEST_LOG_DIR"
echo "Summary: $SUMMARY_LOG"

echo "" >> "$SUMMARY_LOG"
echo "# total=$((PASSED + FAILED)) passed=$PASSED failed=$FAILED" >> "$SUMMARY_LOG"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
