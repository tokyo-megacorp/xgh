#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_file_exists() {
  if [ -f "$1" ]; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $1 does not exist"
    FAIL=$((FAIL+1))
  fi
}

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $1 does not contain '$2'"
    FAIL=$((FAIL+1))
  fi
}

assert_contains_regex() {
  if grep -qE "$2" "$1" 2>/dev/null; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $1 does not match regex '$2'"
    FAIL=$((FAIL+1))
  fi
}

# ── Skill files exist ──────────────────────────────────────
echo "=== Skill file existence ==="
assert_file_exists "skills/investigate/investigate.md"
assert_file_exists "skills/implement-design/implement-design.md"
assert_file_exists "skills/implement-ticket/implement-ticket.md"

# ── Command files exist ────────────────────────────────────
echo "=== Command file existence ==="
assert_file_exists "commands/investigate.md"
assert_file_exists "commands/implement-design.md"
assert_file_exists "commands/implement.md"

# ── investigate skill required sections ────────────────────
echo "=== investigate skill sections ==="
INVEST="skills/investigate/investigate.md"
assert_contains "$INVEST" "Phase 1"
assert_contains "$INVEST" "Phase 2"
assert_contains "$INVEST" "Phase 3"
assert_contains "$INVEST" "Phase 4"
assert_contains "$INVEST" "Context Gathering"
assert_contains "$INVEST" "Interactive Triage"
assert_contains "$INVEST" "Systematic Debug"
assert_contains "$INVEST" "Finding Report"

# investigate skill MCP tool references
echo "=== investigate MCP references ==="
assert_contains "$INVEST" "slack_read_thread"
assert_contains "$INVEST" "slack_search_public"
assert_contains "$INVEST" "cipher_memory_search"
assert_contains "$INVEST" "getJiraIssue"
assert_contains "$INVEST" "searchJiraIssuesUsingJql"
assert_contains "$INVEST" "createJiraIssue"

# investigate skill Superpowers patterns
echo "=== investigate Superpowers patterns ==="
assert_contains "$INVEST" "NO FIXES WITHOUT ROOT CAUSE"
assert_contains "$INVEST" "3 failed hypotheses"
assert_contains "$INVEST" "Iron Law"
assert_contains "$INVEST" "Hard gate"

# investigate skill graceful degradation
echo "=== investigate graceful degradation ==="
assert_contains "$INVEST" "auto-detect"
assert_contains_regex "$INVEST" "[Gg]raceful"

# ── implement-design skill required sections ───────────────
echo "=== implement-design skill sections ==="
DESIGN="skills/implement-design/implement-design.md"
assert_contains "$DESIGN" "Phase 1"
assert_contains "$DESIGN" "Phase 2"
assert_contains "$DESIGN" "Phase 3"
assert_contains "$DESIGN" "Phase 4"
assert_contains "$DESIGN" "Phase 5"
assert_contains "$DESIGN" "Deep Design Mining"
assert_contains "$DESIGN" "Context Enrichment"
assert_contains "$DESIGN" "Interactive State Review"
assert_contains "$DESIGN" "Implementation Plan"
assert_contains "$DESIGN" "Curate"

# implement-design skill MCP tool references
echo "=== implement-design MCP references ==="
assert_contains "$DESIGN" "get_design_context"
assert_contains "$DESIGN" "get_screenshot"
assert_contains "$DESIGN" "get_metadata"
assert_contains "$DESIGN" "get_figjam"
assert_contains "$DESIGN" "get_variable_defs"
assert_contains "$DESIGN" "get_code_connect_map"
assert_contains "$DESIGN" "cipher_memory_search"

# implement-design skill Superpowers patterns
echo "=== implement-design Superpowers patterns ==="
assert_contains "$DESIGN" "TDD"
assert_contains "$DESIGN" "writing-plans"

# ── implement-ticket skill required sections ───────────────
echo "=== implement-ticket skill sections ==="
TICKET="skills/implement-ticket/implement-ticket.md"
assert_contains "$TICKET" "Phase 1"
assert_contains "$TICKET" "Phase 2"
assert_contains "$TICKET" "Phase 3"
assert_contains "$TICKET" "Phase 4"
assert_contains "$TICKET" "Phase 5"
assert_contains "$TICKET" "Phase 6"
assert_contains "$TICKET" "Ticket Deep Dive"
assert_contains "$TICKET" "Cross-Platform Context"
assert_contains "$TICKET" "Context Interview"
assert_contains "$TICKET" "Design Proposal"
assert_contains "$TICKET" "Implementation Plan"
assert_contains "$TICKET" "Execute"

# implement-ticket skill MCP tool references
echo "=== implement-ticket MCP references ==="
assert_contains "$TICKET" "getJiraIssue"
assert_contains "$TICKET" "slack_search_public"
assert_contains "$TICKET" "get_design_context"
assert_contains "$TICKET" "cipher_memory_search"
assert_contains "$TICKET" "cipher_extract_and_operate_memory"

# implement-ticket skill Superpowers patterns
echo "=== implement-ticket Superpowers patterns ==="
assert_contains "$TICKET" "NO IMPLEMENTATION WITHOUT APPROVED DESIGN"
assert_contains "$TICKET" "Hard gate"
assert_contains "$TICKET" "brainstorming"
assert_contains "$TICKET" "one question at a time"
assert_contains "$TICKET" "TDD"
assert_contains "$TICKET" "subagent"

# ── Commands reference their skills ────────────────────────
echo "=== Command-skill references ==="
assert_contains "commands/investigate.md" "investigate"
assert_contains "commands/implement-design.md" "implement-design"
assert_contains "commands/implement.md" "implement-ticket"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
