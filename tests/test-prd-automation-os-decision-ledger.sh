#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

# ── Automation OS Decision Ledger PRD Validation ─────────────────────────────
# Validates the decision-ledger PRD/test-spec contract when the OMX plan
# artifacts are present. The artifacts are runtime-scoped and normally
# git-ignored, so CI without the plans exits successfully with an explicit skip.
# ─────────────────────────────────────────────────────────────────────────────

PASS=0
FAIL=0

main_repo_root() {
  local common_dir
  common_dir="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  if [ -n "$common_dir" ]; then
    (cd "$(dirname "$common_dir")" 2>/dev/null && pwd) || true
  fi
}

find_file() {
  local env_path="$1"
  local filename="$2"

  if [ -n "$env_path" ]; then
    printf '%s\n' "$env_path"
    return 0
  fi

  local root
  root="$(main_repo_root)"

  local candidates=(
    ".omx/plans/$filename"
    "../../../../../.omx/plans/$filename"
  )

  if [ -n "$root" ]; then
    candidates+=("$root/.omx/plans/$filename")
  fi

  local candidate
  for candidate in "${candidates[@]}"; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

assert_contains() {
  local label="$1"
  local expected="$2"
  local file="$3"

  if grep -qF "$expected" "$file"; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected artifact to contain: $expected"
    FAIL=$((FAIL + 1))
  fi
}

assert_heading() {
  local label="$1"
  local heading="$2"
  local file="$3"

  if grep -qE "^#{1,3}[[:space:]]+$heading$" "$file"; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — missing heading: $heading"
    FAIL=$((FAIL + 1))
  fi
}

assert_all_contains() {
  local label="$1"
  local file="$2"
  shift 2

  local expected
  for expected in "$@"; do
    assert_contains "$label: $expected" "$expected" "$file"
  done
}

assert_exact_recommendation_options() {
  local file="$1"
  local count
  count=$(grep -cE '^([0-9]+\. `?(refocus|retire|defer with blocking evidence gaps)`?)$' "$file" || true)
  if [ "$count" -eq 3 ]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: recommendation options — expected exactly 3 outcome bullets, found $count"
    FAIL=$((FAIL + 1))
  fi
}

PRD="$(find_file "${PRD_PATH:-}" "prd-automation-os-decision-ledger.md" || true)"

if [ -z "$PRD" ]; then
  echo "SKIP: .omx/plans/prd-automation-os-decision-ledger.md not present"
  echo "Automation OS decision ledger PRD test: 0 passed, 0 failed (skipped)"
  exit 0
fi

if [ ! -f "$PRD" ]; then
  echo "FAIL: PRD_PATH does not exist: $PRD"
  echo "Automation OS decision ledger PRD test: 0 passed, 1 failed"
  exit 1
fi

# Required structure from the decision-ledger PRD.
assert_heading "metadata" "Metadata" "$PRD"
assert_heading "schema" "Required Decision Ledger Schema" "$PRD"
assert_heading "classification" "Classification Rules" "$PRD"
assert_heading "coverage" "Required Audit Coverage" "$PRD"
assert_heading "acceptance" "Acceptance Criteria" "$PRD"
assert_heading "adr" "ADR — Decision Ledger Before Refocus/Retirement" "$PRD"

# Schema fields every ledger row must require.
assert_all_contains "ledger schema field" "$PRD" \
  '`surface_id`' \
  '`file_paths`' \
  '`evidence_lines`' \
  '`declarative_convergence_justification`' \
  '`self_referential_value`' \
  '`refocus_disposition`' \
  '`retirement_disposition`' \
  '`estimated_effort_risk`' \
  '`final_rationale`'

# Classification values and final recommendation choices are constrained.
assert_all_contains "refocus dispositions" "$PRD" \
  '`Keep`' \
  '`Deprecate-hide`' \
  '`Delete`'
assert_all_contains "retirement dispositions" "$PRD" \
  '`Archive`' \
  '`Migrate concept`' \
  '`Abandon`'
assert_exact_recommendation_options "$PRD"

# Safety gate: this task must remain audit/classification-only.
assert_all_contains "decision boundary" "$PRD" \
  'This PRD authorizes **audit and classification only**.' \
  'No agent may perform the following without separate explicit user approval:' \
  'Archive actions.' \
  'File or surface deletions.' \
  'Repo migration.' \
  'Irreversible public deprecation.' \
  'Public-facing retirement announcement.' \
  '`docs/MIGRATION_GATE.md` must be reviewed before any future migration path.'

# Coverage must include all major live surface families named by the PRD.
assert_all_contains "required audit coverage families" "$PRD" \
  '`README.md`' \
  '`docs/MIGRATION_GATE.md`' \
  '`commands/*.md`' \
  '`skills/`' \
  '`.github/`' \
  '`agents/`' \
  '`config/`' \
  '`hooks/`' \
  '`templates/`' \
  '`tests/`' \
  '`.xgh/context-tree/`' \
  '`.xgh/specs/`' \
  '`.xgh/plans/`' \
  'orphaned or duplicate public references'

assert_all_contains "required command coverage" "$PRD" \
  '`analyze`' \
  '`brief`' \
  '`briefing`' \
  '`calibrate`' \
  '`command-center`' \
  '`config`' \
  '`doctor`' \
  '`help`' \
  '`init-providers`' \
  '`init`' \
  '`retrieve`' \
  '`schedule`' \
  '`seed`' \
  '`status`' \
  '`token-window`' \
  '`track`' \
  '`trigger`'

# Acceptance criteria should keep the deliverable evidence-backed and reversible.
assert_all_contains "acceptance criteria" "$PRD" \
  'Public-surface audit identifies every shipped command/skill/doc surface and classifies it against declarative convergence.' \
  'No orphan/bloat command reference remains unaccounted for.' \
  'Recommendation explains how central automation config becomes if xgh is refocused.' \
  'Deprecated/removal candidates explicitly include generic dispatch, manual curation, and token/window utilities where applicable.' \
  'Retirement option is evaluated honestly.' \
  'Final output recommends exactly one: `refocus`, `retire`, or `defer with blocking evidence gaps`.'

# If the companion test spec is present, validate the PRD still satisfies its
# explicit validation axes. Absence is non-fatal because the assigned artifact is
# the PRD and OMX plan files are runtime-local.
TEST_SPEC="$(find_file "${TEST_SPEC_PATH:-}" "test-spec-automation-os-decision-ledger.md" || true)"
if [ -n "$TEST_SPEC" ]; then
  assert_heading "test spec required checks" "Required Checks" "$TEST_SPEC"
  assert_all_contains "test spec check headings" "$TEST_SPEC" \
    '### 1. Schema Completeness' \
    '### 2. Live Coverage Completeness' \
    '### 3. Evidence Quality' \
    '### 4. Declarative Convergence Check' \
    '### 5. Non-goal Enforcement Check' \
    '### 6. Automation Config Centrality Check' \
    '### 7. Self-Referential Roadmap Check' \
    '### 8. Retirement Honesty and Safety Check' \
    '### 9. Recommendation Validity Check'
  assert_all_contains "test spec stop conditions" "$TEST_SPEC" \
    'Do not proceed to cleanup, archive, migration, or public deprecation in the same execution lane.' \
    'Output states separate user approval is required for irreversible actions.'
fi

echo
echo "Automation OS decision ledger PRD test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
