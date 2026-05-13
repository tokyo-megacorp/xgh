#!/usr/bin/env bash
set -euo pipefail

# ── Automation OS Decision Ledger PRD Validation ─────────────────────────────
# Validates the decision-ledger PRD contract when the OMX plan artifact is
# present. The artifact is runtime-scoped and normally git-ignored, so CI without
# the plan exits successfully with an explicit skip.
# ─────────────────────────────────────────────────────────────────────────────

PASS=0
FAIL=0

find_prd() {
  if [ -n "${PRD_PATH:-}" ]; then
    printf '%s\n' "$PRD_PATH"
    return 0
  fi

  local candidates=(
    ".omx/plans/prd-automation-os-decision-ledger.md"
    "../../../../../.omx/plans/prd-automation-os-decision-ledger.md"
    "/Users/pedro/Developer/xgh/.omx/plans/prd-automation-os-decision-ledger.md"
  )

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
    echo "FAIL: $label — expected PRD to contain: $expected"
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

PRD="$(find_prd || true)"

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
assert_all_contains "required audit coverage" "$PRD" \
  '`README.md`' \
  '`docs/`, especially `docs/MIGRATION_GATE.md`' \
  'Commands: `analyze`, `brief`, `briefing`, `calibrate`, `command-center`, `config`, `doctor`, `help`, `init-providers`, `init`, `retrieve`, `schedule`, `seed`, `status`, `token-window`, `track`, `trigger`.' \
  'Skills: `analyze`, `briefing`, `calibrate`, `command-center`, `config`, `deep-retrieve`, `doctor`, `init-providers`, `init`, `retrieve`, `schedule`, `seed`, `token-window`, `track`, `trigger`.' \
  'Generated/config surfaces: `.github/*`, `agents/*`, `config/*`, `hooks/*`, `templates/*`.' \
  'Tests under `tests/`.' \
  '`.xgh/context-tree/`.' \
  '`.xgh/specs/`.' \
  '`.xgh/plans/`, proposals, roadmap, issue specs, and issue context.' \
  'Any orphaned or duplicate public references discovered during audit.'

# Acceptance criteria should keep the deliverable evidence-backed and reversible.
assert_all_contains "acceptance criteria" "$PRD" \
  'Public-surface audit identifies every shipped command/skill/doc surface and classifies it against declarative convergence.' \
  'No orphan/bloat command reference remains unaccounted for.' \
  'Recommendation explains how central automation config becomes if xgh is refocused.' \
  'Deprecated/removal candidates explicitly include generic dispatch, manual curation, and token/window utilities where applicable.' \
  'Retirement option is evaluated honestly.' \
  'Final output recommends exactly one: `refocus`, `retire`, or `defer with blocking evidence gaps`.'

echo
echo "Automation OS decision ledger PRD test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
