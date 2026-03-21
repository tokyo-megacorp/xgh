#!/usr/bin/env bash
# Run all xgh agent dispatch tests (explicit dispatch prompts)
# Usage: ./run-all.sh
#
# NOTE: This is an opt-in test suite — it invokes claude -p and costs API tokens.
# Do NOT call from tests/test-config.sh.
# Run manually when editing agent definitions or dispatch prompts.
#
# For skill triggering tests, see tests/skill-triggering/run-all.sh.
#
# Environment variables:
#   XGH_TEST_MODEL    — model to use (default: sonnet)
#   XGH_TEST_BUDGET   — max USD per test invocation (default: 0.50)
#   XGH_TEST_LOG_DIR  — persistent log directory (default: /tmp/xgh-test-logs)
#
# Cost estimate: ~8 prompts × 1 turn ≈ ~$0.40 per run (sonnet).
#
# Logs are saved to $XGH_TEST_LOG_DIR (default /tmp/xgh-test-logs):
#   summary.log          — one-line-per-test results
#   agent-xgh--NAME/     — per-agent logs (claude-output.json, prompt.txt, result.txt)
#
# Examples:
#   ./run-all.sh                         # run all 8 agent tests
#   XGH_TEST_MODEL=haiku ./run-all.sh    # cheaper run with haiku

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="$SCRIPT_DIR/prompts"
RUNNER="$SCRIPT_DIR/../skill-triggering/run-agent-test.sh"

export XGH_TEST_LOG_DIR="${XGH_TEST_LOG_DIR:-/tmp/xgh-test-logs}"
mkdir -p "$XGH_TEST_LOG_DIR"
SUMMARY_LOG="$XGH_TEST_LOG_DIR/summary.log"

# ── Agent dispatch tests (explicit prompts) ─────────────────────────────────
AGENT_TESTS=(
    "xgh:code-reviewer:code-reviewer.txt"
    "xgh:collaboration-dispatcher:collaboration-dispatcher.txt"
    "xgh:pipeline-doctor:pipeline-doctor.txt"
    "xgh:context-curator:context-curator.txt"
    "xgh:investigation-lead:investigation-lead.txt"
    "xgh:pr-reviewer:pr-reviewer.txt"
    "xgh:retrieval-auditor:retrieval-auditor.txt"
    "xgh:onboarding-guide:onboarding-guide.txt"
)

echo "=== xgh Agent Dispatch Tests ==="
echo "Plugin dir: $(cd "$SCRIPT_DIR/../.." && pwd)"
echo "Model:  ${XGH_TEST_MODEL:-sonnet}"
echo "Logs:   $XGH_TEST_LOG_DIR"
echo ""

echo "# xgh agent dispatch test results — $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SUMMARY_LOG"
echo "# model=${XGH_TEST_MODEL:-sonnet}" >> "$SUMMARY_LOG"
echo "" >> "$SUMMARY_LOG"

PASSED=0
FAILED=0
RESULTS=()

for entry in "${AGENT_TESTS[@]}"; do
    AGENT="${entry%:*}"
    PROMPT_FILE="${entry##*:}"
    FULL_PROMPT="$PROMPTS_DIR/$PROMPT_FILE"

    if [ ! -f "$FULL_PROMPT" ]; then
        echo "⚠️  SKIP: No prompt file for $AGENT ($FULL_PROMPT)"
        echo "SKIP [agent] $AGENT — missing prompt" >> "$SUMMARY_LOG"
        continue
    fi

    echo "--- Testing agent: $AGENT ---"

    if "$RUNNER" "$AGENT" "$FULL_PROMPT"; then
        PASSED=$((PASSED + 1))
        RESULTS+=("✅ [agent] $AGENT")
        echo "PASS [agent] $AGENT" >> "$SUMMARY_LOG"
    else
        FAILED=$((FAILED + 1))
        RESULTS+=("❌ [agent] $AGENT")
        echo "FAIL [agent] $AGENT" >> "$SUMMARY_LOG"
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
