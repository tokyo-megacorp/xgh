#!/usr/bin/env bash
# test-multi-agent.sh — Validates agent definitions and frontmatter conventions

PASS=0; FAIL=0
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"

assert_file_exists() {
  if [ -f "$1" ]; then
    echo "PASS: $2"; PASS=$((PASS+1))
  else
    echo "FAIL: $2 — missing: $1"; FAIL=$((FAIL+1))
  fi
}

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then
    echo "PASS: $3"; PASS=$((PASS+1))
  else
    echo "FAIL: $3 — '$2' not found in $1"; FAIL=$((FAIL+1))
  fi
}

# ── All agent files exist ───────────────────────────────────────────────────
assert_file_exists "$PLUGIN_DIR/agents/code-reviewer.md"              "code-reviewer exists"
assert_file_exists "$PLUGIN_DIR/agents/collaboration-dispatcher.md"   "collaboration-dispatcher exists"
assert_file_exists "$PLUGIN_DIR/agents/pipeline-doctor.md"            "pipeline-doctor exists"
assert_file_exists "$PLUGIN_DIR/agents/context-curator.md"            "context-curator exists"
assert_file_exists "$PLUGIN_DIR/agents/investigation-lead.md"         "investigation-lead exists"
assert_file_exists "$PLUGIN_DIR/agents/pr-reviewer.md"                "pr-reviewer exists"
assert_file_exists "$PLUGIN_DIR/agents/retrieval-auditor.md"          "retrieval-auditor exists"
assert_file_exists "$PLUGIN_DIR/agents/onboarding-guide.md"           "onboarding-guide exists"

# ── Frontmatter structure (all agents must have these) ──────────────────────
for agent in code-reviewer collaboration-dispatcher pipeline-doctor context-curator investigation-lead pr-reviewer retrieval-auditor onboarding-guide; do
  F="$PLUGIN_DIR/agents/${agent}.md"
  assert_contains "$F" "^---"                    "${agent}: has frontmatter delimiter"
  assert_contains "$F" "^name: ${agent}"         "${agent}: name field matches filename"
  assert_contains "$F" "^description:"           "${agent}: has description field"
  assert_contains "$F" "^model:"                 "${agent}: has model field"
  assert_contains "$F" "^capabilities:"          "${agent}: has capabilities field"
  assert_contains "$F" "^tools:"                 "${agent}: has tools field"
  assert_contains "$F" "<example>"               "${agent}: has dispatch examples"
done

# ── Model assignments ───────────────────────────────────────────────────────
assert_contains "$PLUGIN_DIR/agents/code-reviewer.md"              "^model: sonnet"    "code-reviewer: model is sonnet"
assert_contains "$PLUGIN_DIR/agents/collaboration-dispatcher.md"   "^model: sonnet"    "collaboration-dispatcher: model is sonnet"
assert_contains "$PLUGIN_DIR/agents/pipeline-doctor.md"            "^model: sonnet"    "pipeline-doctor: model is sonnet"
assert_contains "$PLUGIN_DIR/agents/context-curator.md"            "^model: haiku"     "context-curator: model is haiku"
assert_contains "$PLUGIN_DIR/agents/investigation-lead.md"         "^model: opus"      "investigation-lead: model is opus"
assert_contains "$PLUGIN_DIR/agents/pr-reviewer.md"                "^model: sonnet"    "pr-reviewer: model is sonnet"
assert_contains "$PLUGIN_DIR/agents/retrieval-auditor.md"          "^model: haiku"     "retrieval-auditor: model is haiku"
assert_contains "$PLUGIN_DIR/agents/onboarding-guide.md"           "^model: sonnet"    "onboarding-guide: model is sonnet"

# ── Tool grants ─────────────────────────────────────────────────────────────
# Agents with Bash access (review/investigation/diagnosis agents)
# Check specifically in the tools: line to avoid false positives from prose mentioning "Bash"
assert_contains "$PLUGIN_DIR/agents/code-reviewer.md"      'tools:.*Bash'  "code-reviewer: has Bash access"
assert_contains "$PLUGIN_DIR/agents/pipeline-doctor.md"     'tools:.*Bash'  "pipeline-doctor: has Bash access"
assert_contains "$PLUGIN_DIR/agents/investigation-lead.md"  'tools:.*Bash'  "investigation-lead: has Bash access"
assert_contains "$PLUGIN_DIR/agents/pr-reviewer.md"         'tools:.*Bash'  "pr-reviewer: has Bash access"

# Read-only agents (no Bash in tools line)
for agent in collaboration-dispatcher context-curator onboarding-guide retrieval-auditor; do
  F="$PLUGIN_DIR/agents/${agent}.md"
  if grep -q 'tools:.*Bash' "$F" 2>/dev/null; then
    echo "FAIL: ${agent} should NOT have Bash in tools"; FAIL=$((FAIL+1))
  else
    echo "PASS: ${agent}: no Bash in tools (read-only)"; PASS=$((PASS+1))
  fi
done

# ── Agent-specific content ──────────────────────────────────────────────────
# code-reviewer
assert_contains "$PLUGIN_DIR/agents/code-reviewer.md"   "Correctness"     "code-reviewer: checks correctness"
assert_contains "$PLUGIN_DIR/agents/code-reviewer.md"   "lcm_search"      "code-reviewer: uses lcm_search"
assert_contains "$PLUGIN_DIR/agents/code-reviewer.md"   "lcm_store"       "code-reviewer: uses lcm_store"

# collaboration-dispatcher
assert_contains "$PLUGIN_DIR/agents/collaboration-dispatcher.md"  "thread"      "dispatcher: manages threads"
assert_contains "$PLUGIN_DIR/agents/collaboration-dispatcher.md"  "lcm_store"   "dispatcher: uses lcm_store"

# pipeline-doctor
assert_contains "$PLUGIN_DIR/agents/pipeline-doctor.md"  "provider"     "pipeline-doctor: checks providers"
assert_contains "$PLUGIN_DIR/agents/pipeline-doctor.md"  "scheduler"    "pipeline-doctor: checks scheduler"
assert_contains "$PLUGIN_DIR/agents/pipeline-doctor.md"  "inbox"        "pipeline-doctor: checks inbox"
assert_contains "$PLUGIN_DIR/agents/pipeline-doctor.md"  "lcm_doctor"   "pipeline-doctor: uses lcm_doctor"

# context-curator
assert_contains "$PLUGIN_DIR/agents/context-curator.md"  "context-tree"   "context-curator: references context tree"
assert_contains "$PLUGIN_DIR/agents/context-curator.md"  "freshness"      "context-curator: checks freshness"
assert_contains "$PLUGIN_DIR/agents/context-curator.md"  "manifest"       "context-curator: checks manifest"

# investigation-lead
assert_contains "$PLUGIN_DIR/agents/investigation-lead.md"  "hypothes"    "investigation-lead: forms hypotheses"
assert_contains "$PLUGIN_DIR/agents/investigation-lead.md"  "evidence"    "investigation-lead: gathers evidence"
assert_contains "$PLUGIN_DIR/agents/investigation-lead.md"  "root cause"  "investigation-lead: finds root cause"

# pr-reviewer
assert_contains "$PLUGIN_DIR/agents/pr-reviewer.md"  "gh pr"         "pr-reviewer: uses gh CLI"
assert_contains "$PLUGIN_DIR/agents/pr-reviewer.md"  "diff"          "pr-reviewer: reviews diffs"
assert_contains "$PLUGIN_DIR/agents/pr-reviewer.md"  "convention"    "pr-reviewer: checks conventions"

# retrieval-auditor
assert_contains "$PLUGIN_DIR/agents/retrieval-auditor.md"  "provider"    "retrieval-auditor: audits providers"
assert_contains "$PLUGIN_DIR/agents/retrieval-auditor.md"  "fetch"       "retrieval-auditor: checks fetches"
assert_contains "$PLUGIN_DIR/agents/retrieval-auditor.md"  "quality"     "retrieval-auditor: measures quality"

# onboarding-guide
assert_contains "$PLUGIN_DIR/agents/onboarding-guide.md"  "architecture"   "onboarding-guide: covers architecture"
assert_contains "$PLUGIN_DIR/agents/onboarding-guide.md"  "convention"     "onboarding-guide: covers conventions"
assert_contains "$PLUGIN_DIR/agents/onboarding-guide.md"  "context-tree"   "onboarding-guide: references context tree"

# ── Result ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
