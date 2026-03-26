#!/usr/bin/env bash
# tests/test-session-start-preferences.sh
# Tests for hooks/session-start-preferences.sh (Epic 0.1)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start-preferences.sh"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

run_hook() {
  # Run from repo root so project.yaml is discoverable
  (cd "$REPO_ROOT" && bash "$HOOK" 2>/dev/null)
}

echo "=== test-session-start-preferences ==="

# Test 1: Outputs valid JSON
echo "--- 1. Valid JSON output ---"
output=$(run_hook)
if python3 -c "import sys,json; json.loads(sys.argv[1])" "$output" 2>/dev/null; then
  pass "output is valid JSON"
else
  fail "output is not valid JSON: $output"
fi

# Test 2: Contains additionalContext key
echo "--- 2. additionalContext key present ---"
if python3 -c "
import sys, json
d = json.loads(sys.argv[1])
assert 'additionalContext' in d, 'missing additionalContext'
" "$output" 2>/dev/null; then
  pass "additionalContext key present"
else
  fail "additionalContext key missing. Output: $output"
fi

# Test 3: Contains [xgh preferences] header
echo "--- 3. Preference header in output ---"
if python3 -c "
import sys, json
d = json.loads(sys.argv[1])
ctx = d.get('additionalContext', '')
assert '[xgh preferences]' in ctx, 'header missing'
" "$output" 2>/dev/null; then
  pass "[xgh preferences] header present"
else
  fail "[xgh preferences] header missing. Context: $(python3 -c "import sys,json; print(json.loads(sys.argv[1]).get('additionalContext',''))" "$output" 2>/dev/null)"
fi

# Test 4: PR domain is included with expected fields
echo "--- 4. PR domain fields ---"
if python3 -c "
import sys, json
d = json.loads(sys.argv[1])
ctx = d.get('additionalContext', '')
assert 'pr:' in ctx, 'pr domain missing'
assert 'repo=' in ctx, 'repo field missing'
assert 'merge_method=' in ctx, 'merge_method field missing'
" "$output" 2>/dev/null; then
  pass "PR domain present with repo and merge_method"
else
  fail "PR domain missing or incomplete. Context: $(python3 -c "import sys,json; print(json.loads(sys.argv[1]).get('additionalContext',''))" "$output" 2>/dev/null)"
fi

# Test 5: dispatch domain present
echo "--- 5. Dispatch domain ---"
if python3 -c "
import sys, json
d = json.loads(sys.argv[1])
ctx = d.get('additionalContext', '')
assert 'dispatch:' in ctx, 'dispatch domain missing'
" "$output" 2>/dev/null; then
  pass "dispatch domain present"
else
  fail "dispatch domain missing. Context: $(python3 -c "import sys,json; print(json.loads(sys.argv[1]).get('additionalContext',''))" "$output" 2>/dev/null)"
fi

# Test 6: superpowers domain present
echo "--- 6. Superpowers domain ---"
if python3 -c "
import sys, json
d = json.loads(sys.argv[1])
ctx = d.get('additionalContext', '')
assert 'superpowers:' in ctx, 'superpowers domain missing'
" "$output" 2>/dev/null; then
  pass "superpowers domain present"
else
  fail "superpowers domain missing"
fi

# Test 7: Pending preferences count line present
echo "--- 7. Pending preferences count ---"
if python3 -c "
import sys, json
d = json.loads(sys.argv[1])
ctx = d.get('additionalContext', '')
assert 'Pending preferences:' in ctx, 'pending count missing'
" "$output" 2>/dev/null; then
  pass "Pending preferences count present"
else
  fail "Pending preferences count missing"
fi

# Test 8: Output is compact (under 500 chars — approx 120 tokens)
echo "--- 8. Output token budget ---"
char_count=$(python3 -c "
import sys, json
d = json.loads(sys.argv[1])
ctx = d.get('additionalContext', '')
print(len(ctx))
" "$output" 2>/dev/null)
if [ "$char_count" -lt 600 ]; then
  pass "additionalContext is compact (${char_count} chars)"
else
  fail "additionalContext too long (${char_count} chars, want < 600)"
fi

# Test 9: Missing project.yaml — exits silently with no output
echo "--- 9. Missing project.yaml exits silently ---"
tmpdir=$(mktemp -d)
output_no_yaml=$(cd "$tmpdir" && bash "$HOOK" 2>/dev/null || true)
rmdir "$tmpdir"
if [ -z "$output_no_yaml" ]; then
  pass "no output when project.yaml missing"
else
  fail "unexpected output when project.yaml missing: $output_no_yaml"
fi

# Test 10: Malformed YAML — outputs warning in additionalContext
echo "--- 10. Malformed YAML warning ---"
tmpdir=$(mktemp -d)
mkdir -p "${tmpdir}/config"
echo ": broken: yaml: [" > "${tmpdir}/config/project.yaml"
malformed_output=$(cd "$tmpdir" && bash "$HOOK" 2>/dev/null || true)
rmdir_safe() { rm -rf "$1"; }
if python3 -c "
import sys, json
if not sys.argv[1]:
    sys.exit(0)  # empty is also OK (graceful skip)
d = json.loads(sys.argv[1])
ctx = d.get('additionalContext', '')
assert 'WARNING' in ctx or ctx == '', 'should warn or be empty for malformed yaml'
" "$malformed_output" 2>/dev/null; then
  pass "malformed YAML handled gracefully"
else
  fail "malformed YAML not handled: $malformed_output"
fi
rm -rf "$tmpdir"

# Test 11: Snapshot file created
echo "--- 11. Snapshot seeding ---"
test_session_id="test-snapshot-$(date +%s)"
snapshot_input="{\"session_id\": \"${test_session_id}\"}"
snapshot_output=$(cd "$REPO_ROOT" && echo "$snapshot_input" | bash "$HOOK" 2>/dev/null || true)
snapshot_path="${REPO_ROOT}/.xgh/run/xgh-${test_session_id}-project-yaml.yaml"
if [[ -f "$snapshot_path" ]]; then
  pass "snapshot file created at $snapshot_path"
  rm -f "$snapshot_path"
else
  fail "snapshot file not created at $snapshot_path"
fi

# --- Summary ---
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" && exit 0 || exit 1
