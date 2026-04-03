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

assert_contains() {
  if grep -qi "$2" "$1" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 missing '$2'"
    FAIL=$((FAIL + 1))
  fi
}

# --- Source the library ---
assert_contains "lib/config-reader.sh" "load_pr_pref"
assert_contains "lib/config-reader.sh" "probe_pr_field"
assert_contains "lib/config-reader.sh" "cache_pr_pref"

# --- Functional tests using real project.yaml ---
source lib/config-reader.sh

# CLI override wins
result=$(load_pr_pref "provider" "gitlab" "")
assert_equals "CLI override wins" "gitlab" "$result"

# Project default (no CLI override, no branch)
result=$(load_pr_pref "provider" "" "")
assert_equals "Project default: provider" "github" "$result"

result=$(load_pr_pref "repo" "" "")
assert_equals "Project default: repo" "tokyo-megacorp/xgh" "$result"

result=$(load_pr_pref "reviewer" "" "")
assert_equals "Project default: reviewer" "copilot-pull-request-reviewer[bot]" "$result"

result=$(load_pr_pref "reviewer_comment_author" "" "")
assert_equals "Project default: reviewer_comment_author" "Copilot" "$result"

result=$(load_pr_pref "merge_method" "" "")
assert_equals "Project default: merge_method" "squash" "$result"

# Branch-specific override
result=$(load_pr_pref "merge_method" "" "main")
assert_equals "Branch override: main merge_method" "merge" "$result"

result=$(load_pr_pref "merge_method" "" "develop")
assert_equals "Branch override: develop merge_method" "squash" "$result"

# CLI override beats branch override
result=$(load_pr_pref "merge_method" "rebase" "main")
assert_equals "CLI beats branch" "rebase" "$result"

# Branch override for non-merge_method field
result=$(load_pr_pref "required_approvals" "" "main")
assert_equals "Branch override: main required_approvals" "1" "$result"

# Boolean field (review_on_push)
result=$(load_pr_pref "review_on_push" "" "")
assert_equals "Boolean field: review_on_push" "true" "$result"

# Unset field returns empty
result=$(load_pr_pref "nonexistent_field" "" "")
assert_equals "Unset field returns empty" "" "$result"

# --- Profile tests ---
# load_active_profile: returns empty when file does not exist
PROFILE_FILE="${HOME}/.xgh/active-profile"
PROFILE_BACKUP=""
if [[ -f "$PROFILE_FILE" ]]; then
  PROFILE_BACKUP=$(cat "$PROFILE_FILE")
  rm -f "$PROFILE_FILE"
fi

result=$(load_active_profile)
assert_equals "load_active_profile: empty when no file" "" "$result"

# load_active_profile: returns profile name when file exists
mkdir -p "${HOME}/.xgh"
printf 'work' > "$PROFILE_FILE"
result=$(load_active_profile)
assert_equals "load_active_profile: returns profile name" "work" "$result"

# load_active_profile: trims whitespace/newlines
printf 'personal\n' > "$PROFILE_FILE"
result=$(load_active_profile)
assert_equals "load_active_profile: trims newline" "personal" "$result"

# Profile override: when a profile is active and config/project.yaml has profiles: section,
# profile override wins over project default.
# We use a temp project.yaml with a work profile that overrides pr.merge_method.
ORIG_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
TMP_PROFILE_REPO=$(mktemp -d)
trap 'rm -rf "$TMP_PROFILE_REPO"' EXIT
mkdir -p "$TMP_PROFILE_REPO/config"
cat > "$TMP_PROFILE_REPO/config/project.yaml" << 'YAMLEOF'
name: test-profile
preferences:
  pr:
    provider: github
    repo: test/repo
    merge_method: squash
profiles:
  work:
    description: "Work context"
    preferences:
      pr:
        merge_method: merge
YAMLEOF

# Initialize a git repo in the temp dir so _pref_project_yaml can locate project.yaml
git -C "$TMP_PROFILE_REPO" init -q
git -C "$TMP_PROFILE_REPO" config user.email "test@test.com"
git -C "$TMP_PROFILE_REPO" config user.name "Test"

printf 'work' > "$PROFILE_FILE"

# Resolve preferences.sh absolute path from the repo root (tests/ is a sibling of lib/)
_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
_PREFS_SH="${_REPO_ROOT}/lib/preferences.sh"

# Source preferences.sh directly with the temp repo as the working directory so
# _pref_project_yaml resolves to the temp project.yaml.
result=$(cd "$TMP_PROFILE_REPO" && source "$_PREFS_SH" && load_pr_pref "merge_method" "" "")
assert_equals "Profile override: work profile overrides merge_method" "merge" "$result"

# Without profile active, should fall back to project default (squash)
rm -f "$PROFILE_FILE"
result=$(cd "$TMP_PROFILE_REPO" && source "$_PREFS_SH" && load_pr_pref "merge_method" "" "")
assert_equals "No profile: project default merge_method=squash" "squash" "$result"

# CLI override beats profile override
printf 'work' > "$PROFILE_FILE"
result=$(cd "$TMP_PROFILE_REPO" && source "$_PREFS_SH" && load_pr_pref "merge_method" "rebase" "")
assert_equals "CLI beats profile override" "rebase" "$result"

# Restore original active-profile state
rm -f "$PROFILE_FILE"
if [[ -n "$PROFILE_BACKUP" ]]; then
  printf '%s' "$PROFILE_BACKUP" > "$PROFILE_FILE"
fi

echo ""
echo "Config reader test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
