#!/usr/bin/env bash
# Run all xgh skill and agent triggering tests
# Usage: ./run-all.sh [--skills-only | --agents-only]
#
# NOTE: This is an opt-in test suite — it invokes claude -p and costs API tokens.
# Do NOT call from tests/test-config.sh.
# Run manually when editing skill/agent trigger descriptions.
#
# Cost estimate: ~18 prompts × 1 turn ≈ ~$0.90 per full suite run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="$SCRIPT_DIR/prompts"

FILTER="${1:-all}"   # --skills-only, --agents-only, or all (default)

# ── Skill tests ─────────────────────────────────────────────────────────────
# Format: "xgh:skill:prompt_file" — colon separates namespace:skill from filename
SKILL_TESTS=(
    "xgh:retrieve:retrieve.txt"
    "xgh:analyze:analyze.txt"
    "xgh:briefing:briefing.txt"
    "xgh:implement:implement.txt"
    "xgh:investigate:investigate.txt"
    "xgh:track:track.txt"
    "xgh:doctor:doctor.txt"
    "xgh:index:index.txt"
    "xgh:trigger:trigger.txt"
    "xgh:schedule:schedule.txt"
)

# ── Agent tests ─────────────────────────────────────────────────────────────
# Format: "xgh:agent-name:prompt_file" — uses run-agent-test.sh instead of run-test.sh
AGENT_TESTS=(
    "xgh:code-reviewer:agent-code-reviewer.txt"
    "xgh:collaboration-dispatcher:agent-collaboration-dispatcher.txt"
    "xgh:pipeline-doctor:agent-pipeline-doctor.txt"
    "xgh:context-curator:agent-context-curator.txt"
    "xgh:investigation-lead:agent-investigation-lead.txt"
    "xgh:pr-reviewer:agent-pr-reviewer.txt"
    "xgh:retrieval-auditor:agent-retrieval-auditor.txt"
    "xgh:onboarding-guide:agent-onboarding-guide.txt"
)

echo "=== xgh Skill & Agent Triggering Test Suite ==="
echo "Plugin dir: $(cd "$SCRIPT_DIR/../.." && pwd)"
echo "Filter: $FILTER"
echo ""

PASSED=0
FAILED=0
RESULTS=()

run_skill_tests() {
    for entry in "${SKILL_TESTS[@]}"; do
        SKILL="${entry%:*}"
        PROMPT_FILE="${entry##*:}"
        FULL_PROMPT="$PROMPTS_DIR/$PROMPT_FILE"

        if [ ! -f "$FULL_PROMPT" ]; then
            echo "⚠️  SKIP: No prompt file for $SKILL ($FULL_PROMPT)"
            continue
        fi

        echo "--- Testing skill: $SKILL ---"

        if "$SCRIPT_DIR/run-test.sh" "$SKILL" "$FULL_PROMPT"; then
            PASSED=$((PASSED + 1))
            RESULTS+=("✅ [skill] $SKILL")
        else
            FAILED=$((FAILED + 1))
            RESULTS+=("❌ [skill] $SKILL")
        fi

        echo ""
    done
}

run_agent_tests() {
    for entry in "${AGENT_TESTS[@]}"; do
        AGENT="${entry%:*}"
        PROMPT_FILE="${entry##*:}"
        FULL_PROMPT="$PROMPTS_DIR/$PROMPT_FILE"

        if [ ! -f "$FULL_PROMPT" ]; then
            echo "⚠️  SKIP: No prompt file for $AGENT ($FULL_PROMPT)"
            continue
        fi

        echo "--- Testing agent: $AGENT ---"

        if "$SCRIPT_DIR/run-agent-test.sh" "$AGENT" "$FULL_PROMPT"; then
            PASSED=$((PASSED + 1))
            RESULTS+=("✅ [agent] $AGENT")
        else
            FAILED=$((FAILED + 1))
            RESULTS+=("❌ [agent] $AGENT")
        fi

        echo ""
    done
}

case "$FILTER" in
    --skills-only)
        run_skill_tests
        ;;
    --agents-only)
        run_agent_tests
        ;;
    *)
        run_skill_tests
        run_agent_tests
        ;;
esac

echo "=== Summary ==="
for result in "${RESULTS[@]}"; do
    echo "  $result"
done
echo ""
echo "Passed: $PASSED / $((PASSED + FAILED))"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
