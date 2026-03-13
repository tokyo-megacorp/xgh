#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${SCRIPT_DIR}/scripts/ct-frontmatter.sh"
source "${SCRIPT_DIR}/scripts/ct-manifest.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); echo "FAIL: $label — expected '$expected', got '$actual'"
  fi
}

# --- Setup: create a context tree with entries across 2 domains ---
ROOT="$TMP/context-tree"
mkdir -p "$ROOT/backend/auth"
mkdir -p "$ROOT/frontend/components"

cat > "$ROOT/backend/auth/jwt-patterns.md" <<'EOF'
---
title: JWT Patterns
maturity: core
importance: 92
tags: [auth, jwt]
updatedAt: 2026-03-13T00:00:00Z
---
JWT token patterns and best practices.
EOF

cat > "$ROOT/backend/auth/oauth-flows.md" <<'EOF'
---
title: OAuth Flows
maturity: validated
importance: 78
tags: [auth, oauth]
updatedAt: 2026-03-12T00:00:00Z
---
OAuth 2.0 flow documentation.
EOF

cat > "$ROOT/frontend/components/button-system.md" <<'EOF'
---
title: Button System
maturity: draft
importance: 45
tags: [ui, components]
updatedAt: 2026-03-11T00:00:00Z
---
Button component design system.
EOF

cat > "$ROOT/frontend/components/form-patterns.md" <<'EOF'
---
title: Form Patterns
maturity: validated
importance: 60
tags: [ui, forms]
updatedAt: 2026-03-10T00:00:00Z
---
Form patterns and validation.
EOF

# --- Test ct_manifest_init ---
ct_manifest_init "$ROOT"
assert_eq "init creates manifest" "true" "$([ -f "$ROOT/_manifest.json" ] && echo true || echo false)"

# Verify init JSON structure
INIT_VERSION=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print(m['version'])")
assert_eq "init version" "1.0.0" "$INIT_VERSION"

INIT_TEAM=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print(m['team'])")
assert_eq "init team" "${XGH_TEAM:-my-team}" "$INIT_TEAM"

INIT_ENTRIES=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print(len(m['entries']))")
assert_eq "init empty entries" "0" "$INIT_ENTRIES"

INIT_HAS_CREATED=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print('created' in m)")
assert_eq "init has created" "True" "$INIT_HAS_CREATED"

INIT_HAS_REBUILT=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print('lastRebuilt' in m)")
assert_eq "init has lastRebuilt" "True" "$INIT_HAS_REBUILT"

# --- Test ct_manifest_init on existing manifest (should not overwrite) ---
OLD_CREATED=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print(m['created'])")
ct_manifest_init "$ROOT"
NEW_CREATED=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print(m['created'])")
assert_eq "init preserves existing" "$OLD_CREATED" "$NEW_CREATED"

# --- Test ct_manifest_add (upsert with all 6 fields) ---
ct_manifest_add "$ROOT" "backend/auth/jwt-patterns.md"
ENTRY_COUNT=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print(len(m['entries']))")
assert_eq "add first entry" "1" "$ENTRY_COUNT"

# Verify all 6 fields
ENTRY_FIELDS=$(python3 -c "
import json
m = json.load(open('$ROOT/_manifest.json'))
e = m['entries'][0]
fields = ['path','title','maturity','importance','tags','updatedAt']
print(all(f in e for f in fields))
")
assert_eq "add has all 6 fields" "True" "$ENTRY_FIELDS"

ENTRY_TITLE=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print(m['entries'][0]['title'])")
assert_eq "add correct title" "JWT Patterns" "$ENTRY_TITLE"

ENTRY_MATURITY=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print(m['entries'][0]['maturity'])")
assert_eq "add correct maturity" "core" "$ENTRY_MATURITY"

ENTRY_IMPORTANCE=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print(m['entries'][0]['importance'])")
assert_eq "add correct importance" "92" "$ENTRY_IMPORTANCE"

# Upsert same path — should not duplicate
ct_manifest_add "$ROOT" "backend/auth/jwt-patterns.md"
ENTRY_COUNT_AFTER=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print(len(m['entries']))")
assert_eq "add upsert no duplicate" "1" "$ENTRY_COUNT_AFTER"

# --- Test ct_manifest_remove ---
ct_manifest_add "$ROOT" "backend/auth/oauth-flows.md"
ct_manifest_remove "$ROOT" "backend/auth/jwt-patterns.md"
REMAINING=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print(m['entries'][0]['path'])")
assert_eq "remove correct entry" "backend/auth/oauth-flows.md" "$REMAINING"

REMAINING_COUNT=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print(len(m['entries']))")
assert_eq "remove count" "1" "$REMAINING_COUNT"

# --- Test ct_manifest_rebuild ---
ct_manifest_rebuild "$ROOT"
REBUILD_COUNT=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print(len(m['entries']))")
assert_eq "rebuild entry count" "4" "$REBUILD_COUNT"

# --- Test ct_manifest_list ---
LIST_OUTPUT=$(ct_manifest_list "$ROOT")
assert_eq "list contains jwt" "true" "$(echo "$LIST_OUTPUT" | grep -q 'backend/auth/jwt-patterns.md' && echo true || echo false)"

# --- Test ct_manifest_update_indexes ---
ct_manifest_update_indexes "$ROOT"
assert_eq "index backend exists" "true" "$([ -f "$ROOT/backend/_index.md" ] && echo true || echo false)"
assert_eq "index frontend exists" "true" "$([ -f "$ROOT/frontend/_index.md" ] && echo true || echo false)"

# --- Test flat schema (no domains key) ---
HAS_DOMAINS=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print('domains' in m)")
assert_eq "no domains key (flat)" "False" "$HAS_DOMAINS"

HAS_ENTRIES=$(python3 -c "import json; m=json.load(open('$ROOT/_manifest.json')); print('entries' in m)")
assert_eq "has entries key (flat)" "True" "$HAS_ENTRIES"

echo ""
echo "Manifest tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
