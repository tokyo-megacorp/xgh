#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${SCRIPT_DIR}/scripts/ct-frontmatter.sh"
source "${SCRIPT_DIR}/scripts/ct-manifest.sh"
source "${SCRIPT_DIR}/scripts/ct-archive.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    FAIL=$((FAIL+1))
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label (file not found: $path)"
    FAIL=$((FAIL+1))
  fi
}

assert_file_not_exists() {
  local label="$1" path="$2"
  if [[ ! -f "$path" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label (file should not exist: $path)"
    FAIL=$((FAIL+1))
  fi
}

assert_contains() {
  local label="$1" file="$2" pattern="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label (pattern '$pattern' not found in $file)"
    FAIL=$((FAIL+1))
  fi
}

# --- Setup ---
ROOT="$TMP/ctx"
mkdir -p "$ROOT/backend/auth" "$ROOT/frontend/ui" "$ROOT/infra"
ct_manifest_init "$ROOT"

# Create test entries
# 1. draft, importance=20 -> should be archived
cat > "$ROOT/backend/auth/low-draft.md" << 'EOF'
---
title: Low Draft
maturity: draft
importance: 20
tags: [auth]
updatedAt: 2025-01-01T00:00:00Z
---

Some draft content about auth.
EOF
ct_manifest_add "$ROOT" "backend/auth/low-draft.md"

# 2. draft, importance=34 -> should be archived (boundary)
cat > "$ROOT/backend/auth/boundary-34.md" << 'EOF'
---
title: Boundary 34
maturity: draft
importance: 34
tags: [auth]
updatedAt: 2025-01-01T00:00:00Z
---

Draft at boundary 34.
EOF
ct_manifest_add "$ROOT" "backend/auth/boundary-34.md"

# 3. draft, importance=35 -> should NOT be archived (boundary)
cat > "$ROOT/frontend/ui/boundary-35.md" << 'EOF'
---
title: Boundary 35
maturity: draft
importance: 35
tags: [ui]
updatedAt: 2025-01-01T00:00:00Z
---

Draft at boundary 35.
EOF
ct_manifest_add "$ROOT" "frontend/ui/boundary-35.md"

# 4. validated, importance=10 -> should NOT be archived
cat > "$ROOT/frontend/ui/validated-low.md" << 'EOF'
---
title: Validated Low
maturity: validated
importance: 10
tags: [ui]
updatedAt: 2025-01-01T00:00:00Z
---

Validated entry, low importance.
EOF
ct_manifest_add "$ROOT" "frontend/ui/validated-low.md"

# 5. core, importance=5 -> should NOT be archived
cat > "$ROOT/infra/core-low.md" << 'EOF'
---
title: Core Low
maturity: core
importance: 5
tags: [infra]
updatedAt: 2025-01-01T00:00:00Z
---

Core entry, very low importance.
EOF
ct_manifest_add "$ROOT" "infra/core-low.md"

# Save copy of low-draft for comparison
cp "$ROOT/backend/auth/low-draft.md" "$TMP/low-draft-original.md"

echo "=== Test: ct_archive_run ==="

output=$(ct_archive_run "$ROOT")
archived_count=$(echo "$output" | grep -c "^Archived:" || true)

# 1. Correct count of archived entries
assert_eq "archived count is 2" "2" "$archived_count"

# 2. draft importance=20 original removed
assert_file_not_exists "low-draft original removed" "$ROOT/backend/auth/low-draft.md"

# 3. draft importance=34 original removed
assert_file_not_exists "boundary-34 original removed" "$ROOT/backend/auth/boundary-34.md"

# 4. draft importance=35 still exists
assert_file_exists "boundary-35 still exists" "$ROOT/frontend/ui/boundary-35.md"

# 5. validated importance=10 still exists
assert_file_exists "validated-low still exists" "$ROOT/frontend/ui/validated-low.md"

# 6. core importance=5 still exists
assert_file_exists "core-low still exists" "$ROOT/infra/core-low.md"

# 7. .full.md created for low-draft
assert_file_exists "low-draft .full.md created" "$ROOT/_archived/backend/auth/low-draft.full.md"

# 8. .stub.md created for low-draft
assert_file_exists "low-draft .stub.md created" "$ROOT/_archived/backend/auth/low-draft.stub.md"

# 9. .full.md created for boundary-34
assert_file_exists "boundary-34 .full.md created" "$ROOT/_archived/backend/auth/boundary-34.full.md"

# 10. .full.md is byte-identical to original
if diff -q "$TMP/low-draft-original.md" "$ROOT/_archived/backend/auth/low-draft.full.md" >/dev/null 2>&1; then
  echo "  PASS: .full.md is byte-identical to original"
  PASS=$((PASS+1))
else
  echo "  FAIL: .full.md is NOT byte-identical to original"
  FAIL=$((FAIL+1))
fi

# 11. .stub.md references the full file path
assert_contains "stub references full file path" \
  "$ROOT/_archived/backend/auth/low-draft.stub.md" \
  "_archived/backend/auth/low-draft.full.md"

# 12. Manifest no longer contains low-draft
manifest_has_low_draft=$(python3 -c "
import json
with open('${ROOT}/_manifest.json') as f:
    m = json.load(f)
paths = [e['path'] for e in m['entries']]
print('yes' if 'backend/auth/low-draft.md' in paths else 'no')
")
assert_eq "manifest does not contain low-draft" "no" "$manifest_has_low_draft"

# 13. Manifest still contains boundary-35
manifest_has_b35=$(python3 -c "
import json
with open('${ROOT}/_manifest.json') as f:
    m = json.load(f)
paths = [e['path'] for e in m['entries']]
print('yes' if 'frontend/ui/boundary-35.md' in paths else 'no')
")
assert_eq "manifest still contains boundary-35" "yes" "$manifest_has_b35"

echo ""
echo "=== Test: ct_archive_restore ==="

ct_archive_restore "$ROOT" "backend/auth/low-draft.full.md"

# 14. Restored file exists
assert_file_exists "restored file exists" "$ROOT/backend/auth/low-draft.md"

# 15. Restored file has correct title
restored_title=$(ct_frontmatter_get "$ROOT/backend/auth/low-draft.md" "title")
assert_eq "restored title preserved" "Low Draft" "$restored_title"

# 16. Restored file has correct importance
restored_importance=$(ct_frontmatter_get "$ROOT/backend/auth/low-draft.md" "importance")
assert_eq "restored importance preserved" "20" "$restored_importance"

# 17. .full.md removed after restore
assert_file_not_exists "full.md removed after restore" "$ROOT/_archived/backend/auth/low-draft.full.md"

# 18. .stub.md removed after restore
assert_file_not_exists "stub.md removed after restore" "$ROOT/_archived/backend/auth/low-draft.stub.md"

# 19. Manifest re-registered after restore
manifest_has_restored=$(python3 -c "
import json
with open('${ROOT}/_manifest.json') as f:
    m = json.load(f)
paths = [e['path'] for e in m['entries']]
print('yes' if 'backend/auth/low-draft.md' in paths else 'no')
")
assert_eq "manifest re-registered after restore" "yes" "$manifest_has_restored"

echo ""
echo "=== Results ==="
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
