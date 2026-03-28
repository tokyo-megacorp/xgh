#!/usr/bin/env bash
# test-config-drift.sh — Tests for scripts/check-config-drift.sh
# Covers: all match (pass), one missing (warn), multiple missing (warn)
set -euo pipefail

PASS=0; FAIL=0

assert_exit_zero() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $label — expected exit 0, got non-zero"
    FAIL=$((FAIL+1))
  fi
}

assert_output_contains() {
  local label="$1"; local expected="$2"; shift 2
  local out
  out=$("$@" 2>&1 || true)
  if echo "$out" | grep -qF "$expected"; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $label — expected output to contain: $expected"
    echo "  actual output: $out"
    FAIL=$((FAIL+1))
  fi
}

assert_output_not_contains() {
  local label="$1"; local unexpected="$2"; shift 2
  local out
  out=$("$@" 2>&1 || true)
  if echo "$out" | grep -qF "$unexpected"; then
    echo "FAIL: $label — expected output NOT to contain: $unexpected"
    echo "  actual output: $out"
    FAIL=$((FAIL+1))
  else
    PASS=$((PASS+1))
  fi
}

# ── Fixtures ─────────────────────────────────────────────────────────────────

TMPDIR_DRIFT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_DRIFT"' EXIT

INGEST_ALL_MATCH="$TMPDIR_DRIFT/ingest-all-match.yaml"
INGEST_ONE_MISSING="$TMPDIR_DRIFT/ingest-one-missing.yaml"
INGEST_MULTI_MISSING="$TMPDIR_DRIFT/ingest-multi-missing.yaml"
INGEST_INACTIVE_ONLY="$TMPDIR_DRIFT/ingest-inactive-only.yaml"
PROVIDER_FULL="$TMPDIR_DRIFT/provider-full.yaml"
PROVIDER_PARTIAL="$TMPDIR_DRIFT/provider-partial.yaml"
PROVIDER_EMPTY="$TMPDIR_DRIFT/provider-empty.yaml"
PROVIDER_ABSENT="$TMPDIR_DRIFT/provider-does-not-exist.yaml"

# All active repos present in provider
cat > "$INGEST_ALL_MATCH" <<'YAML'
projects:
  proj1:
    status: active
    github:
    - owner/repo1
  proj2:
    status: active
    github:
    - owner/repo2
YAML

cat > "$PROVIDER_FULL" <<'YAML'
service: github
mode: cli
sources:
  - project: proj1
    repo: owner/repo1
    types: [issues]
  - project: proj2
    repo: owner/repo2
    types: [issues]
YAML

# One active repo missing from provider
cat > "$INGEST_ONE_MISSING" <<'YAML'
projects:
  present:
    status: active
    github:
    - owner/present-repo
  missing:
    status: active
    github:
    - owner/missing-repo
YAML

cat > "$PROVIDER_PARTIAL" <<'YAML'
service: github
mode: cli
sources:
  - project: present
    repo: owner/present-repo
    types: [issues]
YAML

# Multiple active repos missing
cat > "$INGEST_MULTI_MISSING" <<'YAML'
projects:
  proj1:
    status: active
    github:
    - owner/repo1
  proj2:
    status: active
    github:
    - owner/repo2
  proj3:
    status: active
    github:
    - owner/repo3
YAML

# Inactive projects only — should never warn
cat > "$INGEST_INACTIVE_ONLY" <<'YAML'
projects:
  archived:
    status: inactive
    github:
    - owner/archived-repo
  paused:
    status: paused
    github:
    - owner/paused-repo
YAML

# Empty provider (no sources key)
cat > "$PROVIDER_EMPTY" <<'YAML'
service: github
mode: cli
YAML


# ── Tests ─────────────────────────────────────────────────────────────────────

# 1. All repos present → exit 0, no WARN output
assert_exit_zero \
  "all-match: exit 0" \
  bash scripts/check-config-drift.sh --ingest "$INGEST_ALL_MATCH" --provider "$PROVIDER_FULL"

assert_output_not_contains \
  "all-match: no WARN output" "WARN" \
  bash scripts/check-config-drift.sh --ingest "$INGEST_ALL_MATCH" --provider "$PROVIDER_FULL"

# 2. One missing → exit 0 (non-blocking), WARN line with project name and repo
assert_exit_zero \
  "one-missing: exit 0" \
  bash scripts/check-config-drift.sh --ingest "$INGEST_ONE_MISSING" --provider "$PROVIDER_PARTIAL"

assert_output_contains \
  "one-missing: WARN for missing project" "WARN: project missing (owner/missing-repo)" \
  bash scripts/check-config-drift.sh --ingest "$INGEST_ONE_MISSING" --provider "$PROVIDER_PARTIAL"

assert_output_not_contains \
  "one-missing: no WARN for present project" "owner/present-repo" \
  bash scripts/check-config-drift.sh --ingest "$INGEST_ONE_MISSING" --provider "$PROVIDER_PARTIAL"

# 3. Multiple missing → exit 0, multiple WARN lines
assert_exit_zero \
  "multi-missing: exit 0" \
  bash scripts/check-config-drift.sh --ingest "$INGEST_MULTI_MISSING" --provider "$PROVIDER_PARTIAL"

assert_output_contains \
  "multi-missing: WARN for proj2" "WARN: project proj2 (owner/repo2)" \
  bash scripts/check-config-drift.sh --ingest "$INGEST_MULTI_MISSING" --provider "$PROVIDER_PARTIAL"

assert_output_contains \
  "multi-missing: WARN for proj3" "WARN: project proj3 (owner/repo3)" \
  bash scripts/check-config-drift.sh --ingest "$INGEST_MULTI_MISSING" --provider "$PROVIDER_PARTIAL"

# 4. Inactive projects → no WARN even if not in provider
assert_exit_zero \
  "inactive-only: exit 0" \
  bash scripts/check-config-drift.sh --ingest "$INGEST_INACTIVE_ONLY" --provider "$PROVIDER_EMPTY"

assert_output_not_contains \
  "inactive-only: no WARN for inactive projects" "WARN" \
  bash scripts/check-config-drift.sh --ingest "$INGEST_INACTIVE_ONLY" --provider "$PROVIDER_EMPTY"

# 5. Provider with no sources → still exits 0 with WARNs
assert_exit_zero \
  "empty-provider: exit 0" \
  bash scripts/check-config-drift.sh --ingest "$INGEST_ALL_MATCH" --provider "$PROVIDER_EMPTY"

assert_output_contains \
  "empty-provider: WARN for proj1" "WARN: project proj1 (owner/repo1)" \
  bash scripts/check-config-drift.sh --ingest "$INGEST_ALL_MATCH" --provider "$PROVIDER_EMPTY"

# 6. Script file exists and is executable
if [ -x "scripts/check-config-drift.sh" ]; then
  PASS=$((PASS+1))
else
  echo "FAIL: scripts/check-config-drift.sh is not executable"
  FAIL=$((FAIL+1))
fi

# 7. Missing provider.yaml → exit 0 with WARN (graceful)
assert_exit_zero \
  "absent-provider: exit 0" \
  bash scripts/check-config-drift.sh --ingest "$INGEST_ALL_MATCH" --provider "$PROVIDER_ABSENT"

assert_output_contains \
  "absent-provider: prints WARN about missing file" "WARN" \
  bash scripts/check-config-drift.sh --ingest "$INGEST_ALL_MATCH" --provider "$PROVIDER_ABSENT"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
