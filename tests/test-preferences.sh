#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_equals() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

# --- Source the library ---
source lib/preferences.sh

# ============================================================
# Core utilities
# ============================================================

# _pref_project_yaml should resolve to config/project.yaml
result=$(_pref_project_yaml)
assert_equals "_pref_project_yaml resolves" "$(git rev-parse --show-toplevel)/config/project.yaml" "$result"

# _pref_read_yaml reads a dotted key
result=$(_pref_read_yaml "preferences.pr.provider")
assert_equals "_pref_read_yaml pr.provider" "github" "$result"

result=$(_pref_read_yaml "preferences.pr.merge_method")
assert_equals "_pref_read_yaml pr.merge_method" "squash" "$result"

# _pref_read_yaml returns empty for missing key
result=$(_pref_read_yaml "preferences.pr.nonexistent")
assert_equals "_pref_read_yaml missing key" "" "$result"

# _pref_read_yaml normalizes booleans
result=$(_pref_read_yaml "preferences.pr.review_on_push")
assert_equals "_pref_read_yaml boolean normalization" "true" "$result"

result=$(_pref_read_yaml "preferences.pair_programming.enabled")
assert_equals "_pref_read_yaml boolean normalization (pair)" "true" "$result"

# _pref_read_branch reads branch override
result=$(_pref_read_branch "pr" "main" "merge_method")
assert_equals "_pref_read_branch main merge_method" "merge" "$result"

result=$(_pref_read_branch "pr" "develop" "merge_method")
assert_equals "_pref_read_branch develop merge_method" "squash" "$result"

# _pref_read_branch returns empty for missing branch
result=$(_pref_read_branch "pr" "nonexistent-branch" "merge_method")
assert_equals "_pref_read_branch missing branch" "" "$result"

# _pref_read_branch returns empty for missing field
result=$(_pref_read_branch "pr" "main" "nonexistent_field")
assert_equals "_pref_read_branch missing field" "" "$result"

# _pref_resolve: CLI override wins
result=$(_pref_resolve "pr" "provider" "gitlab" "")
assert_equals "_pref_resolve CLI wins" "gitlab" "$result"

# _pref_resolve: branch override
result=$(_pref_resolve "pr" "merge_method" "" "main")
assert_equals "_pref_resolve branch override" "merge" "$result"

# _pref_resolve: project default
result=$(_pref_resolve "pr" "merge_method" "" "")
assert_equals "_pref_resolve project default" "squash" "$result"

# _pref_resolve: CLI beats branch
result=$(_pref_resolve "pr" "merge_method" "rebase" "main")
assert_equals "_pref_resolve CLI beats branch" "rebase" "$result"

# _pref_resolve: missing returns empty
result=$(_pref_resolve "pr" "nonexistent" "" "")
assert_equals "_pref_resolve missing returns empty" "" "$result"

# _pref_probe_local: provider probe
result=$(_pref_probe_local "provider")
assert_equals "_pref_probe_local provider" "github" "$result"

# ============================================================
# Domain: pr (CLI > target_branch > default > probe)
# ============================================================

# CLI override
result=$(load_pr_pref "provider" "gitlab" "")
assert_equals "pr: CLI override" "gitlab" "$result"

# Project default
result=$(load_pr_pref "provider" "" "")
assert_equals "pr: project default provider" "github" "$result"

result=$(load_pr_pref "repo" "" "")
assert_equals "pr: project default repo" "tokyo-megacorp/xgh" "$result"

result=$(load_pr_pref "merge_method" "" "")
assert_equals "pr: project default merge_method" "squash" "$result"

# Branch override
result=$(load_pr_pref "merge_method" "" "main")
assert_equals "pr: branch override main" "merge" "$result"

result=$(load_pr_pref "required_approvals" "" "main")
assert_equals "pr: branch override required_approvals" "1" "$result"

# CLI beats branch
result=$(load_pr_pref "merge_method" "rebase" "main")
assert_equals "pr: CLI beats branch" "rebase" "$result"

# Boolean field
result=$(load_pr_pref "review_on_push" "" "")
assert_equals "pr: boolean field" "true" "$result"

# Missing field returns empty
result=$(load_pr_pref "nonexistent_field" "" "")
assert_equals "pr: missing field" "" "$result"

# ============================================================
# Domain: dispatch (CLI > default, repo delegates to pr)
# ============================================================

result=$(load_dispatch_pref "default_agent" "custom-agent")
assert_equals "dispatch: CLI override" "custom-agent" "$result"

result=$(load_dispatch_pref "default_agent" "")
assert_equals "dispatch: project default" "xgh:dispatch" "$result"

result=$(load_dispatch_pref "exec_effort" "")
assert_equals "dispatch: exec_effort default" "high" "$result"

# repo delegates to load_pr_pref
result=$(load_dispatch_pref "repo" "")
assert_equals "dispatch: repo delegates to pr" "tokyo-megacorp/xgh" "$result"

result=$(load_dispatch_pref "repo" "my-org/my-repo")
assert_equals "dispatch: repo CLI override" "my-org/my-repo" "$result"

# ============================================================
# Domain: superpowers (CLI > default)
# ============================================================

result=$(load_superpowers_pref "implementation_model" "")
assert_equals "superpowers: implementation_model default" "sonnet" "$result"

result=$(load_superpowers_pref "review_model" "opus4")
assert_equals "superpowers: CLI override" "opus4" "$result"

result=$(load_superpowers_pref "effort" "")
assert_equals "superpowers: effort default" "normal" "$result"

# ============================================================
# Domain: design (CLI > default)
# ============================================================

result=$(load_design_pref "model" "")
assert_equals "design: model default" "opus" "$result"

result=$(load_design_pref "effort" "")
assert_equals "design: effort default" "max" "$result"

result=$(load_design_pref "model" "sonnet")
assert_equals "design: CLI override" "sonnet" "$result"

# ============================================================
# Domain: agents (CLI > default)
# ============================================================

result=$(load_agents_pref "default_model" "")
assert_equals "agents: default_model" "sonnet" "$result"

result=$(load_agents_pref "default_model" "haiku")
assert_equals "agents: CLI override" "haiku" "$result"

# ============================================================
# Domain: pair_programming (CLI > default)
# ============================================================

result=$(load_pair_programming_pref "enabled" "")
assert_equals "pair_programming: enabled default" "true" "$result"

result=$(load_pair_programming_pref "tool" "")
assert_equals "pair_programming: tool default" "xgh:dispatch" "$result"

result=$(load_pair_programming_pref "effort" "low")
assert_equals "pair_programming: CLI override" "low" "$result"

# ============================================================
# Domain: vcs (CLI > branch > default, defaults to current branch)
# ============================================================

# vcs defaults from project.yaml
result=$(load_vcs_pref "commit_format" "" "")
assert_equals "vcs: project default commit_format" "<type>: <description>" "$result"

# Missing field returns empty
result=$(load_vcs_pref "nonexistent_field" "" "")
assert_equals "vcs: missing field returns empty" "" "$result"

result=$(load_vcs_pref "commit_format" "conventional" "")
assert_equals "vcs: CLI override" "conventional" "$result"

# ============================================================
# Domain: testing (CLI > branch > default, defaults to current branch)
# ============================================================

result=$(load_testing_pref "timeout" "" "")
assert_equals "testing: project default timeout" "120" "$result"

result=$(load_testing_pref "nonexistent_field" "" "")
assert_equals "testing: missing field returns empty" "" "$result"

result=$(load_testing_pref "timeout" "30s" "")
assert_equals "testing: CLI override" "30s" "$result"

# ============================================================
# Domain: scheduling (CLI > default)
# ============================================================

result=$(load_scheduling_pref "retrieve_interval" "")
assert_equals "scheduling: project default retrieve_interval" "30m" "$result"

result=$(load_scheduling_pref "nonexistent_field" "")
assert_equals "scheduling: missing field returns empty" "" "$result"

result=$(load_scheduling_pref "retrieve_interval" "5m")
assert_equals "scheduling: CLI override" "5m" "$result"

# ============================================================
# Domain: notifications (CLI > default)
# ============================================================

result=$(load_notifications_pref "delivery" "")
assert_equals "notifications: project default delivery" "inline" "$result"

result=$(load_notifications_pref "nonexistent_field" "")
assert_equals "notifications: missing field returns empty" "" "$result"

result=$(load_notifications_pref "delivery" "slack")
assert_equals "notifications: CLI override" "slack" "$result"

# ============================================================
# Domain: retrieval (CLI > default)
# ============================================================

result=$(load_retrieval_pref "depth" "")
assert_equals "retrieval: project default depth" "normal" "$result"

result=$(load_retrieval_pref "nonexistent_field" "")
assert_equals "retrieval: missing field returns empty" "" "$result"

result=$(load_retrieval_pref "depth" "3")
assert_equals "retrieval: CLI override" "3" "$result"

# ============================================================
# Summary
# ============================================================

echo ""
echo "Preferences test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
