#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${SCRIPT_DIR}/scripts/ct-search.sh"

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

assert_gt() {
  local label="$1" a="$2" b="$3"
  if python3 -c "import sys; sys.exit(0 if float('$a') > float('$b') else 1)"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); echo "FAIL: $label — expected $a > $b"
  fi
}

# --- Set up temp context tree with 4 entries ---
CT="$TMP/context-tree"
mkdir -p "$CT/auth" "$CT/database" "$CT/misc"

# Entry 1: core entry about oauth (matching term: oauth)
cat > "$CT/auth/oauth.md" <<'EOF'
---
title: OAuth Authentication
importance: 80
recency: 0.9
maturity: core
tags: [oauth, auth]
keywords: [oauth, token]
---
OAuth authentication handles token exchange and callback state.
EOF

# Entry 2: draft entry about oauth (matching term: oauth) — identical content to core
cat > "$CT/auth/oauth-draft.md" <<'EOF'
---
title: OAuth Authentication
importance: 80
recency: 0.9
maturity: draft
tags: [oauth, auth]
keywords: [oauth, token]
---
OAuth authentication handles token exchange and callback state.
EOF

# Entry 3: database entry (matching term: database)
cat > "$CT/database/indexing.md" <<'EOF'
---
title: Database Indexing
importance: 50
recency: 0.5
maturity: draft
tags: [database, indexing]
keywords: [btree, vacuum]
---
Database indexing strategies for performance.
EOF

# Entry 4: unrelated entry (no matching terms for "oauth")
cat > "$CT/misc/unrelated.md" <<'EOF'
---
title: Deployment Guide
importance: 30
recency: 0.3
maturity: draft
tags: [deploy, ci]
keywords: [docker, kubernetes]
---
Guide for deploying to production with containers.
EOF

# ---- Test 1: ct_search_run returns results for matching query ----
RESULTS=$(ct_search_run "$CT" "oauth")
COUNT=$(echo "$RESULTS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
assert_gt "search returns results" "$COUNT" "0"

# ---- Test 2: Results include required fields ----
HAS_FIELDS=$(echo "$RESULTS" | python3 -c "
import json, sys
r = json.load(sys.stdin)[0]
keys = {'bm25_score','final_score','path','title','maturity'}
print('yes' if keys.issubset(r.keys()) else 'no')
")
assert_eq "results have required fields" "yes" "$HAS_FIELDS"

# ---- Test 3: Results sorted by final_score descending ----
IS_SORTED=$(echo "$RESULTS" | python3 -c "
import json, sys
rs = json.load(sys.stdin)
scores = [r['final_score'] for r in rs]
print('yes' if scores == sorted(scores, reverse=True) else 'no')
")
assert_eq "sorted by final_score desc" "yes" "$IS_SORTED"

# ---- Test 4: Maturity boost — core entry's final_score is 1.15x draft's ----
BOOST_CHECK=$(echo "$RESULTS" | python3 -c "
import json, sys
rs = json.load(sys.stdin)
core = [r for r in rs if r['maturity'] == 'core']
draft = [r for r in rs if r['maturity'] == 'draft' and 'oauth' in r['path']]
if core and draft:
    ratio = core[0]['final_score'] / draft[0]['final_score']
    print('yes' if abs(ratio - 1.15) < 0.001 else f'no:ratio={ratio:.6f}')
else:
    print('no:missing entries')
")
assert_eq "core boost is 1.15x draft" "yes" "$BOOST_CHECK"

# ---- Test 5: Entries with bm25_score < 0.01 excluded ----
HAS_UNRELATED=$(echo "$RESULTS" | python3 -c "
import json, sys
rs = json.load(sys.stdin)
paths = [r['path'] for r in rs]
print('yes' if any('unrelated' in p for p in paths) else 'no')
")
assert_eq "unrelated entry excluded" "no" "$HAS_UNRELATED"

# ---- Test 6: ct_search_with_cipher merges Cipher results ----
CIPHER_JSON='[{"path":"auth/oauth.md","similarity":0.95},{"path":"extra/new.md","title":"Extra Entry","similarity":0.8}]'
MERGED=$(ct_search_with_cipher "$CT" "oauth" "$CIPHER_JSON")
HAS_EXTRA=$(echo "$MERGED" | python3 -c "
import json, sys
rs = json.load(sys.stdin)
paths = [r['path'] for r in rs]
print('yes' if 'extra/new.md' in paths else 'no')
")
assert_eq "cipher merge includes extra entry" "yes" "$HAS_EXTRA"

# ---- Test 7: Cipher-merged results have cipher_similarity field ----
HAS_CIPHER_FIELD=$(echo "$MERGED" | python3 -c "
import json, sys
rs = json.load(sys.stdin)
has = all('cipher_similarity' in r for r in rs)
print('yes' if has else 'no')
")
assert_eq "cipher results have cipher_similarity" "yes" "$HAS_CIPHER_FIELD"

# ---- Test 8: Cipher merged results sorted by final_score desc ----
CIPHER_SORTED=$(echo "$MERGED" | python3 -c "
import json, sys
rs = json.load(sys.stdin)
scores = [r['final_score'] for r in rs]
print('yes' if scores == sorted(scores, reverse=True) else 'no')
")
assert_eq "cipher results sorted" "yes" "$CIPHER_SORTED"

# ---- Test 9: Empty query returns empty results ----
EMPTY=$(ct_search_run "$CT" "")
EMPTY_COUNT=$(echo "$EMPTY" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
assert_eq "empty query returns empty" "0" "$EMPTY_COUNT"

# ---- Test 10: Database entry excluded from oauth search ----
HAS_DB=$(echo "$RESULTS" | python3 -c "
import json, sys
rs = json.load(sys.stdin)
paths = [r['path'] for r in rs]
print('yes' if any('database' in p for p in paths) else 'no')
")
assert_eq "database entry excluded from oauth search" "no" "$HAS_DB"

echo ""
echo "ct-search tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
