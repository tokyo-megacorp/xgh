# Context Tree Engine Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build the Context Tree Engine — CRUD operations, scoring/maturity system, BM25 search, manifest management, archival, and sync dispatch for `.xgh/context-tree/` knowledge files.

**Architecture:** Bash scripts in `scripts/` implement all context tree operations. A main entry point `scripts/context-tree.sh` dispatches subcommands (create, read, update, delete, list, search, score, archive, sync). A Python helper `scripts/bm25.py` handles TF-IDF/BM25 search (python3 is available on macOS). Tests in `tests/` follow the existing assert pattern from Plan 1.

**Tech Stack:** Bash, Python 3 (for BM25), YAML frontmatter in markdown, JSON (manifest)

**Design doc:** `docs/plans/2026-03-13-xgh-design.md` — Sections 2 (Sync Layer), 3 (Context Tree Structure)

---

## File Structure

```
scripts/
├── context-tree.sh           # Main dispatcher (create/read/update/delete/list/search/score/archive/sync)
├── ct-frontmatter.sh         # Frontmatter parse/write helpers (sourced by other scripts)
├── ct-scoring.sh             # Importance/recency/maturity calculations
├── ct-manifest.sh            # Manifest + index management
├── ct-archive.sh             # Archival and restore logic
├── ct-search.sh              # BM25 search + merge with Cipher
├── ct-sync.sh                # Sync dispatcher (curate + query orchestration)
└── bm25.py                   # Python BM25/TF-IDF search engine
tests/
├── test-ct-crud.sh           # Knowledge file CRUD tests
├── test-ct-frontmatter.sh    # Frontmatter parse/write tests
├── test-ct-scoring.sh        # Scoring + maturity tests
├── test-ct-search.sh         # BM25 search tests
├── test-ct-manifest.sh       # Manifest + index tests
├── test-ct-archive.sh        # Archival tests
└── test-ct-sync.sh           # Sync dispatcher tests
```

---

## Chunk 1: Frontmatter Parser/Writer + Knowledge File CRUD

### Task 1: Frontmatter parser and writer helpers

**Files:**
- Create: `scripts/ct-frontmatter.sh`
- Create: `tests/test-ct-frontmatter.sh`

- [x] **Step 1: Write failing test for frontmatter functions**

Create `tests/test-ct-frontmatter.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' — $3"; FAIL=$((FAIL+1)); fi
}
assert_contains() {
  if echo "$1" | grep -q "$2" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: output missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}
assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
source "${SCRIPT_DIR}/ct-frontmatter.sh"

# Setup temp dir
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# --- Test: write_frontmatter produces valid YAML frontmatter ---
cat > "${TMPDIR}/test1.md" <<'EOF'
## Raw Concept
Some content here.
EOF

write_frontmatter "${TMPDIR}/test1.md" \
  "title" "JWT Token Refresh" \
  "tags" "[auth, jwt]" \
  "keywords" "[refresh-token, rotation]" \
  "importance" "50" \
  "recency" "1.0" \
  "maturity" "draft" \
  "accessCount" "0" \
  "updateCount" "0" \
  "source" "auto-curate" \
  "fromAgent" "claude-code"

assert_file_contains "${TMPDIR}/test1.md" "^---" "frontmatter start delimiter"
assert_file_contains "${TMPDIR}/test1.md" "title: JWT Token Refresh" "title field"
assert_file_contains "${TMPDIR}/test1.md" "importance: 50" "importance field"
assert_file_contains "${TMPDIR}/test1.md" "maturity: draft" "maturity field"
assert_file_contains "${TMPDIR}/test1.md" "createdAt:" "createdAt auto-generated"
assert_file_contains "${TMPDIR}/test1.md" "updatedAt:" "updatedAt auto-generated"
assert_file_contains "${TMPDIR}/test1.md" "## Raw Concept" "body content preserved"

# --- Test: read_frontmatter_field extracts values ---
TITLE=$(read_frontmatter_field "${TMPDIR}/test1.md" "title")
assert_eq "$TITLE" "JWT Token Refresh" "read title"

IMPORTANCE=$(read_frontmatter_field "${TMPDIR}/test1.md" "importance")
assert_eq "$IMPORTANCE" "50" "read importance"

MATURITY=$(read_frontmatter_field "${TMPDIR}/test1.md" "maturity")
assert_eq "$MATURITY" "draft" "read maturity"

# --- Test: update_frontmatter_field changes a single field ---
update_frontmatter_field "${TMPDIR}/test1.md" "importance" "78"
NEW_IMP=$(read_frontmatter_field "${TMPDIR}/test1.md" "importance")
assert_eq "$NEW_IMP" "78" "updated importance"

# Body still intact
assert_file_contains "${TMPDIR}/test1.md" "## Raw Concept" "body after update"

# --- Test: read_frontmatter_body extracts body ---
BODY=$(read_frontmatter_body "${TMPDIR}/test1.md")
assert_contains "$BODY" "Some content here" "body extraction"

# --- Test: file without frontmatter ---
echo "Just plain content" > "${TMPDIR}/plain.md"
PLAIN_TITLE=$(read_frontmatter_field "${TMPDIR}/plain.md" "title")
assert_eq "$PLAIN_TITLE" "" "no frontmatter returns empty"

echo ""
echo "Frontmatter tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

Run to verify failure:
```bash
cd /path/to/xgh && bash tests/test-ct-frontmatter.sh
# Expected: error — ct-frontmatter.sh not found
```

- [x] **Step 2: Implement frontmatter helpers**

Create `scripts/ct-frontmatter.sh`:

```bash
#!/usr/bin/env bash
# ct-frontmatter.sh — YAML frontmatter parse/write helpers for context tree .md files
# Sourced by other scripts; do not execute directly.

# write_frontmatter FILE KEY1 VAL1 KEY2 VAL2 ...
# Prepends YAML frontmatter to FILE. Preserves existing body content.
# Auto-adds createdAt and updatedAt timestamps.
write_frontmatter() {
  local file="$1"; shift
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Read existing body (strip any existing frontmatter)
  local body=""
  if [ -f "$file" ]; then
    body=$(read_frontmatter_body "$file")
  fi

  # Build frontmatter
  {
    echo "---"
    local has_created=0 has_updated=0
    while [ $# -ge 2 ]; do
      local key="$1" val="$2"; shift 2
      echo "${key}: ${val}"
      [ "$key" = "createdAt" ] && has_created=1
      [ "$key" = "updatedAt" ] && has_updated=1
    done
    [ "$has_created" -eq 0 ] && echo "createdAt: ${now}"
    [ "$has_updated" -eq 0 ] && echo "updatedAt: ${now}"
    echo "---"
    echo ""
    echo "$body"
  } > "$file"
}

# read_frontmatter_field FILE FIELD
# Prints the value of FIELD from YAML frontmatter. Empty string if not found.
read_frontmatter_field() {
  local file="$1" field="$2"
  if [ ! -f "$file" ]; then echo ""; return; fi

  # Check if file starts with ---
  local first_line
  first_line=$(head -n 1 "$file")
  if [ "$first_line" != "---" ]; then echo ""; return; fi

  # Extract frontmatter block (between first and second ---)
  awk '
    BEGIN { in_fm=0; count=0 }
    /^---$/ { count++; if (count==1) { in_fm=1; next } else { exit } }
    in_fm { print }
  ' "$file" | grep "^${field}:" | head -1 | sed "s/^${field}: *//"
}

# read_frontmatter_body FILE
# Prints everything after the closing --- of frontmatter.
# If no frontmatter, prints entire file.
read_frontmatter_body() {
  local file="$1"
  if [ ! -f "$file" ]; then echo ""; return; fi

  local first_line
  first_line=$(head -n 1 "$file")
  if [ "$first_line" != "---" ]; then
    cat "$file"
    return
  fi

  # Skip frontmatter, print rest
  awk '
    BEGIN { count=0; past_fm=0 }
    /^---$/ { count++; if (count==2) { past_fm=1; next } next }
    past_fm { print }
  ' "$file"
}

# update_frontmatter_field FILE FIELD NEW_VALUE
# Updates a single field in existing frontmatter. Also bumps updatedAt.
update_frontmatter_field() {
  local file="$1" field="$2" new_val="$3"
  if [ ! -f "$file" ]; then return 1; fi

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local tmpfile
  tmpfile=$(mktemp)

  awk -v field="$field" -v val="$new_val" -v now="$now" '
    BEGIN { in_fm=0; count=0; found=0; updated_ts=0 }
    /^---$/ {
      count++
      if (count == 2 && !found) {
        print field ": " val
      }
      if (count == 2 && !updated_ts) {
        print "updatedAt: " now
      }
      print
      next
    }
    count == 1 && $0 ~ "^" field ": " {
      print field ": " val
      found = 1
      next
    }
    count == 1 && $0 ~ "^updatedAt: " {
      print "updatedAt: " now
      updated_ts = 1
      next
    }
    { print }
  ' "$file" > "$tmpfile"

  mv "$tmpfile" "$file"
}

# has_frontmatter FILE
# Returns 0 if file has YAML frontmatter, 1 otherwise.
has_frontmatter() {
  local file="$1"
  [ -f "$file" ] || return 1
  local first_line
  first_line=$(head -n 1 "$file")
  [ "$first_line" = "---" ]
}

# list_frontmatter_fields FILE
# Prints all field names from frontmatter, one per line.
list_frontmatter_fields() {
  local file="$1"
  if ! has_frontmatter "$file"; then return; fi
  awk '
    BEGIN { count=0 }
    /^---$/ { count++; if (count>=2) exit; next }
    count==1 { split($0, a, ":"); print a[1] }
  ' "$file"
}
```

Run test:
```bash
cd /path/to/xgh && bash tests/test-ct-frontmatter.sh
# Expected: all pass
```

- [x] **Step 3: Commit**

```bash
git add scripts/ct-frontmatter.sh tests/test-ct-frontmatter.sh
git commit -m "Add frontmatter parser/writer for context tree markdown files"
```

---

### Task 2: Knowledge file CRUD — create and read

**Files:**
- Create: `scripts/context-tree.sh`
- Create: `tests/test-ct-crud.sh`

- [x] **Step 1: Write failing test for create + read**

Create `tests/test-ct-crud.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' — $3"; FAIL=$((FAIL+1)); fi
}
assert_file_exists() {
  if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 missing — $2"; FAIL=$((FAIL+1)); fi
}
assert_file_not_exists() {
  if [ ! -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 should not exist — $2"; FAIL=$((FAIL+1)); fi
}
assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}
assert_dir_exists() {
  if [ -d "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: dir $1 missing — $2"; FAIL=$((FAIL+1)); fi
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CT_SCRIPT="${REPO_ROOT}/scripts/context-tree.sh"

# Setup temp project dir
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Initialize a minimal context tree
CT_DIR="${TMPDIR}/.xgh/context-tree"
mkdir -p "$CT_DIR"
cat > "${CT_DIR}/_manifest.json" <<'EOF'
{
  "version": 1,
  "team": "test-team",
  "created": "2026-03-13T00:00:00Z",
  "domains": []
}
EOF

export XGH_CONTEXT_TREE_DIR="$CT_DIR"

# --- Test: create a knowledge file ---
bash "$CT_SCRIPT" create \
  --domain "authentication" \
  --topic "jwt-implementation" \
  --title "JWT Token Refresh Strategy" \
  --tags "auth,jwt,security" \
  --keywords "refresh-token,rotation,expiry" \
  --source "auto-curate" \
  --from-agent "claude-code" \
  --body "## Raw Concept
Tokens should rotate on every refresh call.

## Facts
- category: convention
  fact: Refresh tokens rotate on every use"

EXPECTED_FILE="${CT_DIR}/authentication/jwt-implementation/jwt-token-refresh-strategy.md"
assert_file_exists "$EXPECTED_FILE" "created knowledge file"
assert_file_contains "$EXPECTED_FILE" "title: JWT Token Refresh Strategy" "title in frontmatter"
assert_file_contains "$EXPECTED_FILE" "tags: \[auth, jwt, security\]" "tags in frontmatter"
assert_file_contains "$EXPECTED_FILE" "importance: 10" "initial importance is 10"
assert_file_contains "$EXPECTED_FILE" "recency: 1.0" "initial recency is 1.0"
assert_file_contains "$EXPECTED_FILE" "maturity: draft" "initial maturity is draft"
assert_file_contains "$EXPECTED_FILE" "accessCount: 0" "initial accessCount"
assert_file_contains "$EXPECTED_FILE" "updateCount: 0" "initial updateCount"
assert_file_contains "$EXPECTED_FILE" "Tokens should rotate" "body content"
assert_dir_exists "${CT_DIR}/authentication/jwt-implementation" "topic dir created"

# --- Test: create with subtopic ---
bash "$CT_SCRIPT" create \
  --domain "authentication" \
  --topic "jwt-implementation" \
  --subtopic "refresh-tokens" \
  --title "Token Rotation Policy" \
  --tags "auth,jwt" \
  --keywords "rotation" \
  --source "manual" \
  --from-agent "claude-code" \
  --body "Rotate on every use."

SUBTOPIC_FILE="${CT_DIR}/authentication/jwt-implementation/refresh-tokens/token-rotation-policy.md"
assert_file_exists "$SUBTOPIC_FILE" "subtopic file created"

# --- Test: read a knowledge file ---
READ_OUTPUT=$(bash "$CT_SCRIPT" read --path "authentication/jwt-implementation/jwt-token-refresh-strategy")
assert_eq "$?" "0" "read exits 0"
echo "$READ_OUTPUT" | grep -q "JWT Token Refresh Strategy" && PASS=$((PASS+1)) || { echo "FAIL: read output missing title"; FAIL=$((FAIL+1)); }
echo "$READ_OUTPUT" | grep -q "Tokens should rotate" && PASS=$((PASS+1)) || { echo "FAIL: read output missing body"; FAIL=$((FAIL+1)); }

# --- Test: read bumps accessCount ---
bash "$CT_SCRIPT" read --path "authentication/jwt-implementation/jwt-token-refresh-strategy" > /dev/null
ACCESS=$(grep "accessCount:" "$EXPECTED_FILE" | head -1 | awk '{print $2}')
assert_eq "$ACCESS" "2" "accessCount bumped to 2"

# --- Test: list files ---
LIST_OUTPUT=$(bash "$CT_SCRIPT" list)
echo "$LIST_OUTPUT" | grep -q "jwt-token-refresh-strategy" && PASS=$((PASS+1)) || { echo "FAIL: list missing file"; FAIL=$((FAIL+1)); }
echo "$LIST_OUTPUT" | grep -q "token-rotation-policy" && PASS=$((PASS+1)) || { echo "FAIL: list missing subtopic file"; FAIL=$((FAIL+1)); }

# --- Test: list with domain filter ---
LIST_AUTH=$(bash "$CT_SCRIPT" list --domain "authentication")
echo "$LIST_AUTH" | grep -q "jwt-token-refresh-strategy" && PASS=$((PASS+1)) || { echo "FAIL: filtered list missing file"; FAIL=$((FAIL+1)); }

# --- Test: update a knowledge file ---
bash "$CT_SCRIPT" update \
  --path "authentication/jwt-implementation/jwt-token-refresh-strategy" \
  --body "## Raw Concept
Tokens should rotate on every refresh call. Added: 7-day absolute expiry.

## Facts
- category: convention
  fact: Refresh tokens rotate on every use with 7-day expiry"

assert_file_contains "$EXPECTED_FILE" "7-day absolute expiry" "updated body"
UCOUNT=$(grep "updateCount:" "$EXPECTED_FILE" | head -1 | awk '{print $2}')
assert_eq "$UCOUNT" "1" "updateCount bumped"

# --- Test: update tags ---
bash "$CT_SCRIPT" update \
  --path "authentication/jwt-implementation/jwt-token-refresh-strategy" \
  --tags "auth,jwt,security,token-rotation"

assert_file_contains "$EXPECTED_FILE" "token-rotation" "updated tags"

# --- Test: delete a knowledge file ---
bash "$CT_SCRIPT" delete --path "authentication/jwt-implementation/refresh-tokens/token-rotation-policy"
assert_file_not_exists "$SUBTOPIC_FILE" "deleted file"

# --- Test: create with duplicate title in same location fails ---
bash "$CT_SCRIPT" create \
  --domain "authentication" \
  --topic "jwt-implementation" \
  --title "JWT Token Refresh Strategy" \
  --tags "auth" \
  --keywords "jwt" \
  --source "manual" \
  --from-agent "claude-code" \
  --body "Duplicate." 2>/dev/null && {
    echo "FAIL: duplicate create should fail"; FAIL=$((FAIL+1))
  } || PASS=$((PASS+1))

echo ""
echo "CRUD tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

Run to verify failure:
```bash
cd /path/to/xgh && bash tests/test-ct-crud.sh
# Expected: error — context-tree.sh not found
```

- [x] **Step 2: Implement context-tree.sh with create, read, list, update, delete**

Create `scripts/context-tree.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/ct-frontmatter.sh"

# Resolve context tree directory
CT_DIR="${XGH_CONTEXT_TREE_DIR:-${PWD}/.xgh/context-tree}"

# ── Helpers ────────────────────────────────────────────────

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//'
}

format_tags() {
  # "auth,jwt,security" -> "[auth, jwt, security]"
  local raw="$1"
  local formatted
  formatted=$(echo "$raw" | sed 's/,/, /g')
  echo "[${formatted}]"
}

resolve_path() {
  # Given --domain/--topic/--subtopic/--title, resolve to file path
  local domain="$1" topic="${2:-}" subtopic="${3:-}" title_slug="$4"
  local dir="${CT_DIR}/${domain}"
  [ -n "$topic" ] && dir="${dir}/${topic}"
  [ -n "$subtopic" ] && dir="${dir}/${subtopic}"
  echo "${dir}/${title_slug}.md"
}

usage() {
  echo "Usage: context-tree.sh <command> [options]"
  echo ""
  echo "Commands:"
  echo "  create    Create a new knowledge file"
  echo "  read      Read a knowledge file (bumps accessCount)"
  echo "  update    Update a knowledge file"
  echo "  delete    Delete a knowledge file"
  echo "  list      List knowledge files"
  echo "  search    Search knowledge files (BM25)"
  echo "  score     Run scoring/maturity updates"
  echo "  archive   Archive low-importance drafts"
  echo "  sync      Sync dispatcher (curate/query)"
  exit 1
}

# ── CREATE ─────────────────────────────────────────────────

cmd_create() {
  local domain="" topic="" subtopic="" title="" tags="" keywords=""
  local source="auto-curate" from_agent="" body="" related=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --domain)    domain="$2"; shift 2 ;;
      --topic)     topic="$2"; shift 2 ;;
      --subtopic)  subtopic="$2"; shift 2 ;;
      --title)     title="$2"; shift 2 ;;
      --tags)      tags="$2"; shift 2 ;;
      --keywords)  keywords="$2"; shift 2 ;;
      --source)    source="$2"; shift 2 ;;
      --from-agent) from_agent="$2"; shift 2 ;;
      --body)      body="$2"; shift 2 ;;
      --related)   related="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [ -z "$domain" ] || [ -z "$title" ]; then
    echo "Error: --domain and --title are required" >&2
    exit 1
  fi

  local title_slug
  title_slug=$(slugify "$title")
  local file_path
  file_path=$(resolve_path "$domain" "$topic" "$subtopic" "$title_slug")

  # Check for duplicates
  if [ -f "$file_path" ]; then
    echo "Error: file already exists: ${file_path}" >&2
    exit 1
  fi

  # Create directory structure
  mkdir -p "$(dirname "$file_path")"

  # Write body first so write_frontmatter can preserve it
  echo "$body" > "$file_path"

  # Build frontmatter args
  local fm_args=(
    "title" "$title"
    "tags" "$(format_tags "$tags")"
    "keywords" "$(format_tags "$keywords")"
    "importance" "10"
    "recency" "1.0"
    "maturity" "draft"
    "accessCount" "0"
    "updateCount" "0"
    "source" "$source"
    "fromAgent" "$from_agent"
  )

  if [ -n "$related" ]; then
    fm_args+=("related" "$related")
  fi

  write_frontmatter "$file_path" "${fm_args[@]}"

  echo "Created: ${file_path}"
}

# ── READ ───────────────────────────────────────────────────

cmd_read() {
  local path=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --path) path="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [ -z "$path" ]; then
    echo "Error: --path is required" >&2; exit 1
  fi

  local file_path="${CT_DIR}/${path}.md"
  if [ ! -f "$file_path" ]; then
    echo "Error: file not found: ${file_path}" >&2; exit 1
  fi

  # Bump accessCount
  local current
  current=$(read_frontmatter_field "$file_path" "accessCount")
  current=${current:-0}
  update_frontmatter_field "$file_path" "accessCount" "$((current + 1))"

  # Bump importance by +3 (search hit)
  local imp
  imp=$(read_frontmatter_field "$file_path" "importance")
  imp=${imp:-0}
  local new_imp=$((imp + 3))
  [ "$new_imp" -gt 100 ] && new_imp=100
  update_frontmatter_field "$file_path" "importance" "$new_imp"

  # Output the file
  cat "$file_path"
}

# ── LIST ───────────────────────────────────────────────────

cmd_list() {
  local domain=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --domain) domain="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  local search_dir="$CT_DIR"
  [ -n "$domain" ] && search_dir="${CT_DIR}/${domain}"

  if [ ! -d "$search_dir" ]; then
    echo "No files found." ; return 0
  fi

  # Find all .md files, exclude _index.md, _manifest.json, .stub.md
  find "$search_dir" -name "*.md" \
    ! -name "_index.md" \
    ! -name "context.md" \
    ! -name "*.stub.md" \
    -type f | sort | while read -r f; do
    local rel_path="${f#${CT_DIR}/}"
    local title
    title=$(read_frontmatter_field "$f" "title")
    local maturity
    maturity=$(read_frontmatter_field "$f" "maturity")
    local importance
    importance=$(read_frontmatter_field "$f" "importance")
    printf "%-60s  [%s]  imp:%s\n" "$rel_path" "${maturity:-unknown}" "${importance:-0}"
  done
}

# ── UPDATE ─────────────────────────────────────────────────

cmd_update() {
  local path="" body="" tags="" keywords="" title="" related=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --path)      path="$2"; shift 2 ;;
      --body)      body="$2"; shift 2 ;;
      --tags)      tags="$2"; shift 2 ;;
      --keywords)  keywords="$2"; shift 2 ;;
      --title)     title="$2"; shift 2 ;;
      --related)   related="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [ -z "$path" ]; then
    echo "Error: --path is required" >&2; exit 1
  fi

  local file_path="${CT_DIR}/${path}.md"
  if [ ! -f "$file_path" ]; then
    echo "Error: file not found: ${file_path}" >&2; exit 1
  fi

  # Update body if provided
  if [ -n "$body" ]; then
    # Read all frontmatter fields, rewrite file with new body
    local tmpfile
    tmpfile=$(mktemp)
    # Extract frontmatter lines
    awk '
      BEGIN { count=0 }
      /^---$/ { count++; print; if (count>=2) exit; next }
      count>=1 && count<2 { print }
    ' "$file_path" > "$tmpfile"
    # Append second --- and new body
    echo "---" >> "$tmpfile"
    echo "" >> "$tmpfile"
    echo "$body" >> "$tmpfile"
    mv "$tmpfile" "$file_path"
  fi

  # Update individual fields
  if [ -n "$tags" ]; then
    update_frontmatter_field "$file_path" "tags" "$(format_tags "$tags")"
  fi
  if [ -n "$keywords" ]; then
    update_frontmatter_field "$file_path" "keywords" "$(format_tags "$keywords")"
  fi
  if [ -n "$title" ]; then
    update_frontmatter_field "$file_path" "title" "$title"
  fi
  if [ -n "$related" ]; then
    update_frontmatter_field "$file_path" "related" "$related"
  fi

  # Bump updateCount and importance (+5 per update)
  local uc
  uc=$(read_frontmatter_field "$file_path" "updateCount")
  uc=${uc:-0}
  update_frontmatter_field "$file_path" "updateCount" "$((uc + 1))"

  local imp
  imp=$(read_frontmatter_field "$file_path" "importance")
  imp=${imp:-0}
  local new_imp=$((imp + 5))
  [ "$new_imp" -gt 100 ] && new_imp=100
  update_frontmatter_field "$file_path" "importance" "$new_imp"

  # Reset recency to 1.0 on update
  update_frontmatter_field "$file_path" "recency" "1.0"

  echo "Updated: ${file_path}"
}

# ── DELETE ─────────────────────────────────────────────────

cmd_delete() {
  local path=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --path) path="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [ -z "$path" ]; then
    echo "Error: --path is required" >&2; exit 1
  fi

  local file_path="${CT_DIR}/${path}.md"
  if [ ! -f "$file_path" ]; then
    echo "Error: file not found: ${file_path}" >&2; exit 1
  fi

  rm "$file_path"

  # Clean up empty directories
  local dir
  dir=$(dirname "$file_path")
  while [ "$dir" != "$CT_DIR" ] && [ -d "$dir" ]; do
    if [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
      rmdir "$dir"
      dir=$(dirname "$dir")
    else
      break
    fi
  done

  echo "Deleted: ${file_path}"
}

# ── DISPATCH ───────────────────────────────────────────────

if [ $# -lt 1 ]; then usage; fi

COMMAND="$1"; shift
case "$COMMAND" in
  create)   cmd_create "$@" ;;
  read)     cmd_read "$@" ;;
  list)     cmd_list "$@" ;;
  update)   cmd_update "$@" ;;
  delete)   cmd_delete "$@" ;;
  search)
    source "${SCRIPT_DIR}/ct-search.sh"
    cmd_search "$@"
    ;;
  score)
    source "${SCRIPT_DIR}/ct-scoring.sh"
    cmd_score "$@"
    ;;
  archive)
    source "${SCRIPT_DIR}/ct-archive.sh"
    cmd_archive "$@"
    ;;
  sync)
    source "${SCRIPT_DIR}/ct-sync.sh"
    cmd_sync "$@"
    ;;
  *) echo "Unknown command: $COMMAND" >&2; usage ;;
esac
```

Run test:
```bash
cd /path/to/xgh && bash tests/test-ct-crud.sh
# Expected: all pass
```

- [x] **Step 3: Run test and verify pass**

```bash
bash tests/test-ct-crud.sh
```

- [x] **Step 4: Commit**

```bash
git add scripts/context-tree.sh tests/test-ct-crud.sh
git commit -m "Add context tree CRUD operations (create/read/update/delete/list)"
```

---

## Chunk 2: Scoring Engine + Maturity Promotion

### Task 3: Scoring engine — importance, recency decay, maturity transitions

**Files:**
- Create: `scripts/ct-scoring.sh`
- Create: `tests/test-ct-scoring.sh`

- [x] **Step 1: Write failing test for scoring**

Create `tests/test-ct-scoring.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' — $3"; FAIL=$((FAIL+1)); fi
}
assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="${REPO_ROOT}/scripts"
source "${SCRIPT_DIR}/ct-frontmatter.sh"
source "${SCRIPT_DIR}/ct-scoring.sh"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

CT_DIR="${TMPDIR}/.xgh/context-tree"
mkdir -p "${CT_DIR}/test-domain/test-topic"
export XGH_CONTEXT_TREE_DIR="$CT_DIR"

# --- Helper: create a test file with specific frontmatter ---
create_test_file() {
  local file="$1" importance="$2" recency="$3" maturity="$4" updated_at="${5:-2026-03-13T00:00:00Z}"
  cat > "$file" <<EOF
---
title: Test File
tags: [test]
keywords: [test]
importance: ${importance}
recency: ${recency}
maturity: ${maturity}
accessCount: 5
updateCount: 2
createdAt: 2026-01-01T00:00:00Z
updatedAt: ${updated_at}
source: manual
fromAgent: test
---

Test content.
EOF
}

# --- Test: recency decay calculation ---
# 21-day half-life: after 21 days, recency should be ~0.5
# Formula: recency = e^(-ln(2) * days / 21)
DECAY_21=$(calculate_recency_decay 21)
# Should be approximately 0.50 (allow 0.49-0.51)
echo "21-day decay: $DECAY_21"
DECAY_INT=$(echo "$DECAY_21" | awk '{printf "%d", $1 * 100}')
if [ "$DECAY_INT" -ge 49 ] && [ "$DECAY_INT" -le 51 ]; then
  PASS=$((PASS+1))
else
  echo "FAIL: 21-day decay should be ~0.50, got $DECAY_21"
  FAIL=$((FAIL+1))
fi

# After 0 days, recency should be 1.0
DECAY_0=$(calculate_recency_decay 0)
DECAY_0_INT=$(echo "$DECAY_0" | awk '{printf "%d", $1 * 100}')
assert_eq "$DECAY_0_INT" "100" "0-day decay is 1.0"

# After 42 days (2 half-lives), should be ~0.25
DECAY_42=$(calculate_recency_decay 42)
DECAY_42_INT=$(echo "$DECAY_42" | awk '{printf "%d", $1 * 100}')
if [ "$DECAY_42_INT" -ge 24 ] && [ "$DECAY_42_INT" -le 26 ]; then
  PASS=$((PASS+1))
else
  echo "FAIL: 42-day decay should be ~0.25, got $DECAY_42"
  FAIL=$((FAIL+1))
fi

# --- Test: maturity promotion draft -> validated at importance >= 65 ---
FILE1="${CT_DIR}/test-domain/test-topic/promote-test.md"
create_test_file "$FILE1" "65" "0.9" "draft"
evaluate_maturity "$FILE1"
MAT=$(read_frontmatter_field "$FILE1" "maturity")
assert_eq "$MAT" "validated" "draft promoted to validated at importance 65"

# --- Test: maturity promotion validated -> core at importance >= 85 ---
FILE2="${CT_DIR}/test-domain/test-topic/core-test.md"
create_test_file "$FILE2" "85" "0.9" "validated"
evaluate_maturity "$FILE2"
MAT2=$(read_frontmatter_field "$FILE2" "maturity")
assert_eq "$MAT2" "core" "validated promoted to core at importance 85"

# --- Test: hysteresis — core does NOT demote until importance < 25 (85 - 60) ---
FILE3="${CT_DIR}/test-domain/test-topic/hysteresis-core.md"
create_test_file "$FILE3" "30" "0.5" "core"
evaluate_maturity "$FILE3"
MAT3=$(read_frontmatter_field "$FILE3" "maturity")
assert_eq "$MAT3" "core" "core stays core at importance 30 (above 25 threshold)"

FILE4="${CT_DIR}/test-domain/test-topic/hysteresis-core-demote.md"
create_test_file "$FILE4" "24" "0.3" "core"
evaluate_maturity "$FILE4"
MAT4=$(read_frontmatter_field "$FILE4" "maturity")
assert_eq "$MAT4" "validated" "core demotes to validated at importance 24"

# --- Test: hysteresis — validated does NOT demote until importance < 30 (65 - 35) ---
FILE5="${CT_DIR}/test-domain/test-topic/hysteresis-val.md"
create_test_file "$FILE5" "35" "0.5" "validated"
evaluate_maturity "$FILE5"
MAT5=$(read_frontmatter_field "$FILE5" "maturity")
assert_eq "$MAT5" "validated" "validated stays at importance 35 (above 30 threshold)"

FILE6="${CT_DIR}/test-domain/test-topic/hysteresis-val-demote.md"
create_test_file "$FILE6" "29" "0.3" "validated"
evaluate_maturity "$FILE6"
MAT6=$(read_frontmatter_field "$FILE6" "maturity")
assert_eq "$MAT6" "draft" "validated demotes to draft at importance 29"

# --- Test: apply_recency_decay updates recency field based on updatedAt ---
FILE7="${CT_DIR}/test-domain/test-topic/decay-test.md"
# Set updatedAt to 21 days ago
TWENTY_ONE_DAYS_AGO=$(python3 -c "
from datetime import datetime, timedelta
d = datetime.utcnow() - timedelta(days=21)
print(d.strftime('%Y-%m-%dT%H:%M:%SZ'))
")
create_test_file "$FILE7" "50" "1.0" "draft" "$TWENTY_ONE_DAYS_AGO"
apply_recency_decay "$FILE7"
NEW_RECENCY=$(read_frontmatter_field "$FILE7" "recency")
REC_INT=$(echo "$NEW_RECENCY" | awk '{printf "%d", $1 * 100}')
if [ "$REC_INT" -ge 48 ] && [ "$REC_INT" -le 52 ]; then
  PASS=$((PASS+1))
else
  echo "FAIL: recency after 21 days should be ~0.50, got $NEW_RECENCY"
  FAIL=$((FAIL+1))
fi

# --- Test: cmd_score runs scoring on all files ---
cmd_score --all
# Verify files still have valid frontmatter
assert_file_contains "$FILE1" "maturity:" "scoring preserved maturity field"

echo ""
echo "Scoring tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

Run to verify failure:
```bash
cd /path/to/xgh && bash tests/test-ct-scoring.sh
# Expected: error — ct-scoring.sh not found or functions missing
```

- [x] **Step 2: Implement scoring engine**

Create `scripts/ct-scoring.sh`:

```bash
#!/usr/bin/env bash
# ct-scoring.sh — Importance, recency decay, and maturity promotion/demotion
# Sourced by context-tree.sh; can also be sourced directly for testing.

# Requires ct-frontmatter.sh to be sourced first.

# ── Constants ──────────────────────────────────────────────

HALF_LIFE_DAYS=21
PROMOTE_VALIDATED=65
PROMOTE_CORE=85
DEMOTE_CORE_THRESHOLD=25    # 85 - 60 hysteresis
DEMOTE_VALIDATED_THRESHOLD=30  # 65 - 35 hysteresis

IMPORTANCE_SEARCH_HIT=3
IMPORTANCE_UPDATE=5
IMPORTANCE_MANUAL_CURATE=10

# ── Recency Decay ─────────────────────────────────────────

# calculate_recency_decay DAYS_SINCE_UPDATE
# Returns float 0.0–1.0. Formula: e^(-ln(2) * days / HALF_LIFE)
calculate_recency_decay() {
  local days="$1"
  python3 -c "
import math
days = ${days}
half_life = ${HALF_LIFE_DAYS}
decay = math.exp(-math.log(2) * days / half_life)
print(f'{decay:.4f}')
"
}

# apply_recency_decay FILE
# Reads updatedAt, calculates days elapsed, sets recency field.
apply_recency_decay() {
  local file="$1"
  local updated_at
  updated_at=$(read_frontmatter_field "$file" "updatedAt")
  if [ -z "$updated_at" ]; then return; fi

  local days_elapsed
  days_elapsed=$(python3 -c "
from datetime import datetime
import sys
try:
    updated = datetime.strptime('${updated_at}', '%Y-%m-%dT%H:%M:%SZ')
    now = datetime.utcnow()
    delta = (now - updated).total_seconds() / 86400
    print(int(max(0, delta)))
except:
    print(0)
")

  local new_recency
  new_recency=$(calculate_recency_decay "$days_elapsed")
  update_frontmatter_field "$file" "recency" "$new_recency"
}

# ── Maturity Evaluation ────────────────────────────────────

# evaluate_maturity FILE
# Promotes or demotes maturity based on importance with hysteresis.
evaluate_maturity() {
  local file="$1"
  local importance maturity
  importance=$(read_frontmatter_field "$file" "importance")
  maturity=$(read_frontmatter_field "$file" "maturity")
  importance=${importance:-0}
  maturity=${maturity:-draft}

  local new_maturity="$maturity"

  case "$maturity" in
    draft)
      if [ "$importance" -ge "$PROMOTE_CORE" ]; then
        new_maturity="core"
      elif [ "$importance" -ge "$PROMOTE_VALIDATED" ]; then
        new_maturity="validated"
      fi
      ;;
    validated)
      if [ "$importance" -ge "$PROMOTE_CORE" ]; then
        new_maturity="core"
      elif [ "$importance" -lt "$DEMOTE_VALIDATED_THRESHOLD" ]; then
        new_maturity="draft"
      fi
      ;;
    core)
      if [ "$importance" -lt "$DEMOTE_CORE_THRESHOLD" ]; then
        new_maturity="validated"
      fi
      ;;
  esac

  if [ "$new_maturity" != "$maturity" ]; then
    update_frontmatter_field "$file" "maturity" "$new_maturity"
  fi
}

# ── Importance Bump ────────────────────────────────────────

# bump_importance FILE AMOUNT
# Adds AMOUNT to importance, caps at 100.
bump_importance() {
  local file="$1" amount="$2"
  local imp
  imp=$(read_frontmatter_field "$file" "importance")
  imp=${imp:-0}
  local new_imp=$((imp + amount))
  [ "$new_imp" -gt 100 ] && new_imp=100
  update_frontmatter_field "$file" "importance" "$new_imp"
}

# ── Score All Files ────────────────────────────────────────

# cmd_score [--all]
# Runs recency decay and maturity evaluation on all context tree files.
cmd_score() {
  local ct_dir="${XGH_CONTEXT_TREE_DIR:-${PWD}/.xgh/context-tree}"

  find "$ct_dir" -name "*.md" \
    ! -name "_index.md" \
    ! -name "context.md" \
    ! -name "*.stub.md" \
    -type f | while read -r file; do
    apply_recency_decay "$file"
    evaluate_maturity "$file"
  done

  echo "Scoring complete."
}
```

Run test:
```bash
cd /path/to/xgh && bash tests/test-ct-scoring.sh
# Expected: all pass
```

- [x] **Step 3: Run test and verify pass**

```bash
bash tests/test-ct-scoring.sh
```

- [x] **Step 4: Commit**

```bash
git add scripts/ct-scoring.sh tests/test-ct-scoring.sh
git commit -m "Add scoring engine with recency decay, maturity promotion/demotion, and hysteresis"
```

---

## Chunk 3: BM25 Search

### Task 4: BM25 search engine

**Files:**
- Create: `scripts/bm25.py`
- Create: `scripts/ct-search.sh`
- Create: `tests/test-ct-search.sh`

- [x] **Step 1: Write failing test for BM25 search**

Create `tests/test-ct-search.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' — $3"; FAIL=$((FAIL+1)); fi
}
assert_contains() {
  if echo "$1" | grep -q "$2" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: output missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}
assert_not_contains() {
  if ! echo "$1" | grep -q "$2" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: output should not contain '$2' — $3"; FAIL=$((FAIL+1)); fi
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CT_SCRIPT="${REPO_ROOT}/scripts/context-tree.sh"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

CT_DIR="${TMPDIR}/.xgh/context-tree"
mkdir -p "$CT_DIR"
cat > "${CT_DIR}/_manifest.json" <<'EOF'
{"version":1,"team":"test","created":"2026-03-13T00:00:00Z","domains":[]}
EOF

export XGH_CONTEXT_TREE_DIR="$CT_DIR"

# Create test files with different content
bash "$CT_SCRIPT" create \
  --domain "authentication" \
  --topic "jwt" \
  --title "JWT Token Refresh" \
  --tags "auth,jwt,security" \
  --keywords "refresh-token,rotation" \
  --source "manual" \
  --from-agent "test" \
  --body "Refresh tokens should rotate on every use. The JWT implementation uses RSA256 for signing."

bash "$CT_SCRIPT" create \
  --domain "api-design" \
  --topic "rest" \
  --title "REST API Conventions" \
  --tags "api,rest,conventions" \
  --keywords "endpoints,http-methods" \
  --source "manual" \
  --from-agent "test" \
  --body "Use kebab-case for URLs. POST for creation, PUT for full replacement, PATCH for partial updates."

bash "$CT_SCRIPT" create \
  --domain "authentication" \
  --topic "oauth" \
  --title "OAuth2 GitHub SSO" \
  --tags "auth,oauth,github" \
  --keywords "sso,github,oauth2" \
  --source "manual" \
  --from-agent "test" \
  --body "GitHub SSO uses OAuth2 authorization code flow. Tokens are stored in secure HTTP-only cookies."

# --- Test: search for "JWT refresh token" should rank JWT file first ---
RESULT=$(bash "$CT_SCRIPT" search --query "JWT refresh token")
assert_contains "$RESULT" "jwt-token-refresh" "JWT file found in results"

# --- Test: search for "OAuth GitHub" should find OAuth file ---
RESULT2=$(bash "$CT_SCRIPT" search --query "OAuth GitHub SSO")
assert_contains "$RESULT2" "oauth2-github-sso" "OAuth file found"

# --- Test: search for "REST API endpoints" should find REST file ---
RESULT3=$(bash "$CT_SCRIPT" search --query "REST API endpoints conventions")
assert_contains "$RESULT3" "rest-api-conventions" "REST file found"

# --- Test: search for nonexistent term returns no results ---
RESULT4=$(bash "$CT_SCRIPT" search --query "kubernetes deployment helm")
# Should either be empty or have very low scores
assert_not_contains "$RESULT4" "ERROR" "no error on empty search"

# --- Test: search with --limit ---
RESULT5=$(bash "$CT_SCRIPT" search --query "auth token" --limit 1)
LINE_COUNT=$(echo "$RESULT5" | grep -c "\.md" || true)
if [ "$LINE_COUNT" -le 1 ]; then PASS=$((PASS+1)); else echo "FAIL: limit 1 returned $LINE_COUNT results"; FAIL=$((FAIL+1)); fi

# --- Test: BM25 python module works standalone ---
PYTHON_RESULT=$(python3 "${REPO_ROOT}/scripts/bm25.py" "$CT_DIR" "JWT refresh token rotation" 5)
assert_contains "$PYTHON_RESULT" "jwt-token-refresh" "Python BM25 finds JWT file"

echo ""
echo "Search tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

Run to verify failure:
```bash
cd /path/to/xgh && bash tests/test-ct-search.sh
# Expected: error — ct-search.sh / bm25.py not found
```

- [x] **Step 2: Implement BM25 Python module**

Create `scripts/bm25.py`:

```python
#!/usr/bin/env python3
"""
BM25 search over context tree markdown files.

Usage: python3 bm25.py <context_tree_dir> <query> [max_results]

Outputs JSON array of results:
  [{"path": "relative/path.md", "score": 0.85, "title": "...", "importance": 50, "recency": 0.9, "maturity": "draft"}, ...]
"""

import sys
import os
import re
import math
import json
from pathlib import Path


def parse_frontmatter(filepath):
    """Parse YAML frontmatter from a markdown file. Returns (fields_dict, body_text)."""
    fields = {}
    body_lines = []
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except (IOError, UnicodeDecodeError):
        return fields, ""

    if not lines or lines[0].strip() != '---':
        return fields, ''.join(lines)

    in_frontmatter = False
    fm_count = 0
    for line in lines:
        stripped = line.strip()
        if stripped == '---':
            fm_count += 1
            if fm_count == 1:
                in_frontmatter = True
                continue
            elif fm_count == 2:
                in_frontmatter = False
                continue
        if in_frontmatter:
            match = re.match(r'^(\w+):\s*(.*)', line.strip())
            if match:
                key, val = match.group(1), match.group(2)
                fields[key] = val
        elif fm_count >= 2:
            body_lines.append(line)

    return fields, ''.join(body_lines)


def tokenize(text):
    """Simple whitespace + punctuation tokenizer, lowercased."""
    text = text.lower()
    text = re.sub(r'[^\w\s-]', ' ', text)
    tokens = text.split()
    # Remove very short tokens
    return [t for t in tokens if len(t) > 1]


def parse_list_field(val):
    """Parse '[a, b, c]' into ['a', 'b', 'c']."""
    if not val:
        return []
    val = val.strip('[]')
    return [x.strip() for x in val.split(',') if x.strip()]


class BM25:
    """BM25 ranking over a corpus of documents."""

    def __init__(self, k1=1.5, b=0.75):
        self.k1 = k1
        self.b = b
        self.docs = []       # list of {"path", "tokens", "fields"}
        self.df = {}         # document frequency per term
        self.avgdl = 0
        self.N = 0

    def add_document(self, path, tokens, fields):
        self.docs.append({"path": path, "tokens": tokens, "fields": fields})
        for t in set(tokens):
            self.df[t] = self.df.get(t, 0) + 1

    def build(self):
        self.N = len(self.docs)
        if self.N == 0:
            self.avgdl = 1
            return
        total = sum(len(d["tokens"]) for d in self.docs)
        self.avgdl = total / self.N if self.N > 0 else 1

    def score(self, query_tokens):
        """Score all documents against query. Returns list of (index, score)."""
        results = []
        for i, doc in enumerate(self.docs):
            s = 0.0
            dl = len(doc["tokens"])
            tf_map = {}
            for t in doc["tokens"]:
                tf_map[t] = tf_map.get(t, 0) + 1

            for qt in query_tokens:
                if qt not in self.df:
                    continue
                tf = tf_map.get(qt, 0)
                if tf == 0:
                    continue
                idf = math.log((self.N - self.df[qt] + 0.5) / (self.df[qt] + 0.5) + 1)
                numerator = tf * (self.k1 + 1)
                denominator = tf + self.k1 * (1 - self.b + self.b * dl / self.avgdl)
                s += idf * numerator / denominator

            results.append((i, s))
        return results


def search(context_tree_dir, query, max_results=10):
    """Search context tree files using BM25. Returns JSON results."""
    ct_path = Path(context_tree_dir)
    if not ct_path.exists():
        return []

    # Collect all .md files (exclude special files)
    md_files = []
    for f in ct_path.rglob('*.md'):
        name = f.name
        if name.startswith('_') or name == 'context.md' or name.endswith('.stub.md'):
            continue
        md_files.append(f)

    if not md_files:
        return []

    # Build BM25 index
    bm25 = BM25()
    for f in md_files:
        fields, body = parse_frontmatter(str(f))
        # Combine title, tags, keywords, and body for search
        text_parts = []
        if 'title' in fields:
            # Title gets extra weight by repeating
            text_parts.extend([fields['title']] * 3)
        for list_field in ['tags', 'keywords']:
            if list_field in fields:
                items = parse_list_field(fields[list_field])
                text_parts.extend(items * 2)  # tags/keywords weighted 2x
        text_parts.append(body)

        tokens = tokenize(' '.join(text_parts))
        rel_path = str(f.relative_to(ct_path))
        bm25.add_document(rel_path, tokens, fields)

    bm25.build()

    # Score query
    query_tokens = tokenize(query)
    if not query_tokens:
        return []

    scores = bm25.score(query_tokens)

    # Normalize BM25 scores to 0-1
    max_score = max((s for _, s in scores), default=0)
    if max_score > 0:
        scores = [(i, s / max_score) for i, s in scores]

    # Filter zero scores and sort
    scores = [(i, s) for i, s in scores if s > 0.01]
    scores.sort(key=lambda x: x[1], reverse=True)
    scores = scores[:max_results]

    # Build results
    results = []
    for idx, bm25_score in scores:
        doc = bm25.docs[idx]
        fields = doc["fields"]

        importance = 0
        try:
            importance = int(fields.get("importance", "0"))
        except ValueError:
            pass

        recency = 0.0
        try:
            recency = float(fields.get("recency", "0"))
        except ValueError:
            pass

        maturity = fields.get("maturity", "draft")

        results.append({
            "path": doc["path"],
            "bm25_score": round(bm25_score, 4),
            "title": fields.get("title", ""),
            "importance": importance,
            "recency": recency,
            "maturity": maturity,
        })

    return results


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: bm25.py <context_tree_dir> <query> [max_results]", file=sys.stderr)
        sys.exit(1)

    ct_dir = sys.argv[1]
    query = sys.argv[2]
    max_results = int(sys.argv[3]) if len(sys.argv) > 3 else 10

    results = search(ct_dir, query, max_results)
    print(json.dumps(results, indent=2))
```

- [x] **Step 3: Implement search shell wrapper**

Create `scripts/ct-search.sh`:

```bash
#!/usr/bin/env bash
# ct-search.sh — BM25 search + optional merge with Cipher results
# Sourced by context-tree.sh

# cmd_search --query QUERY [--limit N] [--cipher-results JSON]
cmd_search() {
  local query="" limit=10 cipher_results=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --query)          query="$2"; shift 2 ;;
      --limit)          limit="$2"; shift 2 ;;
      --cipher-results) cipher_results="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "$query" ]; then
    echo "Error: --query is required" >&2; return 1
  fi

  local ct_dir="${XGH_CONTEXT_TREE_DIR:-${PWD}/.xgh/context-tree}"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Run BM25 search
  local bm25_json
  bm25_json=$(python3 "${script_dir}/bm25.py" "$ct_dir" "$query" "$limit")

  if [ -z "$cipher_results" ]; then
    # No Cipher results — output BM25 results directly with final scoring
    python3 -c "
import json, sys

bm25 = json.loads('''${bm25_json}''')

# Apply combined scoring: since no cipher, use BM25 + importance + recency
# score = 0.3 * bm25 + 0.1 * (importance/100) + 0.1 * recency, with maturity boost
results = []
for r in bm25:
    imp_norm = r['importance'] / 100.0
    rec = r['recency']
    bm25_s = r['bm25_score']
    maturity_boost = 1.15 if r['maturity'] == 'core' else 1.0

    # Without cipher, redistribute: 0.6*bm25 + 0.2*importance + 0.2*recency
    score = (0.6 * bm25_s + 0.2 * imp_norm + 0.2 * rec) * maturity_boost
    r['final_score'] = round(score, 4)
    results.append(r)

results.sort(key=lambda x: x['final_score'], reverse=True)
for r in results[:${limit}]:
    mat_tag = f'[{r[\"maturity\"]}]'
    print(f'{r[\"final_score\"]:.3f}  {mat_tag:12s}  {r[\"path\"]:60s}  {r[\"title\"]}')
"
  else
    # Merge BM25 with Cipher results using full formula
    python3 -c "
import json, sys

bm25 = json.loads('''${bm25_json}''')
cipher = json.loads('''${cipher_results}''')

# Build lookup from cipher results by path (or title match)
cipher_map = {}
for c in cipher:
    key = c.get('path', c.get('title', ''))
    cipher_map[key] = c.get('similarity', 0)

results = []
for r in bm25:
    cipher_sim = cipher_map.get(r['path'], 0)
    imp_norm = r['importance'] / 100.0
    rec = r['recency']
    bm25_s = r['bm25_score']
    maturity_boost = 1.15 if r['maturity'] == 'core' else 1.0

    # Full formula: score = (0.5*cipher + 0.3*bm25 + 0.1*importance + 0.1*recency) * maturityBoost
    score = (0.5 * cipher_sim + 0.3 * bm25_s + 0.1 * imp_norm + 0.1 * rec) * maturity_boost
    r['cipher_similarity'] = cipher_sim
    r['final_score'] = round(score, 4)
    results.append(r)

# Add cipher-only results not in BM25
bm25_paths = {r['path'] for r in bm25}
for c in cipher:
    path = c.get('path', '')
    if path and path not in bm25_paths:
        score = (0.5 * c.get('similarity', 0)) * 1.0  # no BM25/importance/recency info
        results.append({
            'path': path,
            'title': c.get('title', ''),
            'cipher_similarity': c.get('similarity', 0),
            'bm25_score': 0,
            'final_score': round(score, 4),
            'maturity': 'unknown',
        })

results.sort(key=lambda x: x['final_score'], reverse=True)
for r in results[:${limit}]:
    mat_tag = f'[{r.get(\"maturity\", \"?\")}]'
    print(f'{r[\"final_score\"]:.3f}  {mat_tag:12s}  {r[\"path\"]:60s}  {r.get(\"title\", \"\")}')
"
  fi
}
```

Run test:
```bash
cd /path/to/xgh && bash tests/test-ct-search.sh
# Expected: all pass
```

- [x] **Step 4: Run test and verify pass**

```bash
bash tests/test-ct-search.sh
```

- [x] **Step 5: Commit**

```bash
git add scripts/bm25.py scripts/ct-search.sh tests/test-ct-search.sh
git commit -m "Add BM25 search engine with combined scoring and Cipher merge support"
```

---

## Chunk 4: Manifest Manager + Index Generation

### Task 5: Manifest and index management

**Files:**
- Create: `scripts/ct-manifest.sh`
- Create: `tests/test-ct-manifest.sh`

- [x] **Step 1: Write failing test for manifest operations**

Create `tests/test-ct-manifest.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' — $3"; FAIL=$((FAIL+1)); fi
}
assert_contains() {
  if echo "$1" | grep -q "$2" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: output missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}
assert_file_exists() {
  if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 missing — $2"; FAIL=$((FAIL+1)); fi
}
assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CT_SCRIPT="${REPO_ROOT}/scripts/context-tree.sh"
SCRIPT_DIR="${REPO_ROOT}/scripts"
source "${SCRIPT_DIR}/ct-frontmatter.sh"
source "${SCRIPT_DIR}/ct-manifest.sh"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

CT_DIR="${TMPDIR}/.xgh/context-tree"
mkdir -p "$CT_DIR"
cat > "${CT_DIR}/_manifest.json" <<'EOF'
{
  "version": 1,
  "team": "test-team",
  "created": "2026-03-13T00:00:00Z",
  "domains": []
}
EOF

export XGH_CONTEXT_TREE_DIR="$CT_DIR"

# Create test knowledge files
bash "$CT_SCRIPT" create \
  --domain "authentication" --topic "jwt" \
  --title "JWT Token Refresh" --tags "auth,jwt" --keywords "jwt,refresh" \
  --source "manual" --from-agent "test" --body "JWT refresh strategy."

bash "$CT_SCRIPT" create \
  --domain "authentication" --topic "oauth" \
  --title "OAuth2 Flow" --tags "auth,oauth" --keywords "oauth2" \
  --source "manual" --from-agent "test" --body "OAuth2 authorization code flow."

bash "$CT_SCRIPT" create \
  --domain "api-design" --topic "rest" \
  --title "REST Conventions" --tags "api,rest" --keywords "rest,conventions" \
  --source "manual" --from-agent "test" --body "Use kebab-case for URLs."

# --- Test: rebuild_manifest creates valid manifest ---
rebuild_manifest "$CT_DIR"

# Check manifest is valid JSON
python3 -c "import json; json.load(open('${CT_DIR}/_manifest.json'))" && PASS=$((PASS+1)) || { echo "FAIL: manifest invalid JSON"; FAIL=$((FAIL+1)); }

# Check manifest has domains
MANIFEST=$(cat "${CT_DIR}/_manifest.json")
assert_contains "$MANIFEST" "authentication" "manifest has authentication domain"
assert_contains "$MANIFEST" "api-design" "manifest has api-design domain"

# Check manifest has entries
assert_contains "$MANIFEST" "jwt-token-refresh" "manifest has JWT entry"
assert_contains "$MANIFEST" "oauth2-flow" "manifest has OAuth entry"
assert_contains "$MANIFEST" "rest-conventions" "manifest has REST entry"

# Check entry count
ENTRY_COUNT=$(python3 -c "
import json
m = json.load(open('${CT_DIR}/_manifest.json'))
total = sum(len(d.get('entries', [])) for d in m.get('domains', []))
print(total)
")
assert_eq "$ENTRY_COUNT" "3" "manifest has 3 total entries"

# --- Test: generate_index creates _index.md per domain ---
generate_index "$CT_DIR"
assert_file_exists "${CT_DIR}/authentication/_index.md" "auth domain _index.md"
assert_file_exists "${CT_DIR}/api-design/_index.md" "api-design domain _index.md"

# Check index content
assert_file_contains "${CT_DIR}/authentication/_index.md" "JWT Token Refresh" "index has JWT title"
assert_file_contains "${CT_DIR}/authentication/_index.md" "OAuth2 Flow" "index has OAuth title"
assert_file_contains "${CT_DIR}/api-design/_index.md" "REST Conventions" "index has REST title"

# --- Test: add_to_manifest adds a single entry ---
bash "$CT_SCRIPT" create \
  --domain "authentication" --topic "sessions" \
  --title "Session Management" --tags "auth,sessions" --keywords "sessions" \
  --source "manual" --from-agent "test" --body "Cookie-based sessions."

add_to_manifest "$CT_DIR" "authentication/sessions/session-management.md" "Session Management" "draft" "10"

MANIFEST2=$(cat "${CT_DIR}/_manifest.json")
assert_contains "$MANIFEST2" "session-management" "added entry in manifest"

# --- Test: remove_from_manifest removes an entry ---
remove_from_manifest "$CT_DIR" "authentication/sessions/session-management.md"
MANIFEST3=$(cat "${CT_DIR}/_manifest.json")
echo "$MANIFEST3" | grep -q "session-management" && { echo "FAIL: entry should be removed"; FAIL=$((FAIL+1)); } || PASS=$((PASS+1))

echo ""
echo "Manifest tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

Run to verify failure:
```bash
cd /path/to/xgh && bash tests/test-ct-manifest.sh
# Expected: error — ct-manifest.sh not found
```

- [x] **Step 2: Implement manifest manager**

Create `scripts/ct-manifest.sh`:

```bash
#!/usr/bin/env bash
# ct-manifest.sh — Manifest (_manifest.json) and index (_index.md) management
# Sourced by context-tree.sh; can also be sourced directly.

# rebuild_manifest CT_DIR
# Scans all .md files and rebuilds _manifest.json from scratch.
rebuild_manifest() {
  local ct_dir="$1"
  local manifest="${ct_dir}/_manifest.json"

  # Read existing manifest for team/version info
  local team version created
  team=$(python3 -c "import json; m=json.load(open('${manifest}')); print(m.get('team','unknown'))" 2>/dev/null || echo "unknown")
  version=$(python3 -c "import json; m=json.load(open('${manifest}')); print(m.get('version',1))" 2>/dev/null || echo "1")
  created=$(python3 -c "import json; m=json.load(open('${manifest}')); print(m.get('created',''))" 2>/dev/null || echo "")

  python3 -c "
import json, os, re, sys
from pathlib import Path

ct_dir = Path('${ct_dir}')
domains = {}

for md_file in sorted(ct_dir.rglob('*.md')):
    name = md_file.name
    if name.startswith('_') or name == 'context.md' or name.endswith('.stub.md'):
        continue

    rel = md_file.relative_to(ct_dir)
    parts = rel.parts
    if len(parts) < 2:
        continue  # need at least domain/file.md

    domain_name = parts[0]
    if domain_name == '_archived':
        continue

    # Parse frontmatter
    fields = {}
    try:
        with open(md_file, 'r') as f:
            lines = f.readlines()
        if lines and lines[0].strip() == '---':
            in_fm = False
            count = 0
            for line in lines:
                if line.strip() == '---':
                    count += 1
                    if count == 1:
                        in_fm = True
                        continue
                    else:
                        break
                if in_fm:
                    m = re.match(r'^(\w+):\s*(.*)', line.strip())
                    if m:
                        fields[m.group(1)] = m.group(2)
    except:
        pass

    if domain_name not in domains:
        domains[domain_name] = {'name': domain_name, 'entries': []}

    entry = {
        'path': str(rel),
        'title': fields.get('title', name.replace('.md', '')),
        'maturity': fields.get('maturity', 'draft'),
        'importance': int(fields.get('importance', '0')),
        'tags': fields.get('tags', '[]'),
        'updatedAt': fields.get('updatedAt', ''),
    }
    domains[domain_name]['entries'].append(entry)

manifest = {
    'version': ${version},
    'team': '${team}',
    'created': '${created}',
    'lastRebuilt': __import__('datetime').datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'domains': list(domains.values()),
}

with open('${manifest}', 'w') as f:
    json.dump(manifest, f, indent=2)
"
}

# add_to_manifest CT_DIR REL_PATH TITLE MATURITY IMPORTANCE
# Adds a single entry to the manifest without full rebuild.
add_to_manifest() {
  local ct_dir="$1" rel_path="$2" title="$3" maturity="$4" importance="$5"
  local manifest="${ct_dir}/_manifest.json"

  python3 -c "
import json, sys
from pathlib import Path

manifest_path = '${manifest}'
rel_path = '${rel_path}'
title = '${title}'
maturity = '${maturity}'
importance = int('${importance}')

with open(manifest_path, 'r') as f:
    m = json.load(f)

# Determine domain from path
parts = Path(rel_path).parts
domain_name = parts[0] if parts else 'unknown'

# Find or create domain
domain = None
for d in m.get('domains', []):
    if d['name'] == domain_name:
        domain = d
        break

if domain is None:
    domain = {'name': domain_name, 'entries': []}
    m.setdefault('domains', []).append(domain)

# Check if entry already exists
existing = [e for e in domain['entries'] if e['path'] == rel_path]
if not existing:
    domain['entries'].append({
        'path': rel_path,
        'title': title,
        'maturity': maturity,
        'importance': importance,
    })

with open(manifest_path, 'w') as f:
    json.dump(m, f, indent=2)
"
}

# remove_from_manifest CT_DIR REL_PATH
# Removes a single entry from the manifest.
remove_from_manifest() {
  local ct_dir="$1" rel_path="$2"
  local manifest="${ct_dir}/_manifest.json"

  python3 -c "
import json

manifest_path = '${manifest}'
rel_path = '${rel_path}'

with open(manifest_path, 'r') as f:
    m = json.load(f)

for domain in m.get('domains', []):
    domain['entries'] = [e for e in domain.get('entries', []) if e['path'] != rel_path]

# Remove empty domains
m['domains'] = [d for d in m.get('domains', []) if d.get('entries')]

with open(manifest_path, 'w') as f:
    json.dump(m, f, indent=2)
"
}

# generate_index CT_DIR
# Generates _index.md for each domain directory with compressed summaries.
generate_index() {
  local ct_dir="$1"

  # Find all domain directories (top-level dirs that aren't special)
  for domain_dir in "${ct_dir}"/*/; do
    [ -d "$domain_dir" ] || continue
    local domain_name
    domain_name=$(basename "$domain_dir")
    # Skip _archived and other special dirs
    [[ "$domain_name" == _* ]] && continue

    local index_file="${domain_dir}/_index.md"

    python3 -c "
import os, re
from pathlib import Path

domain_dir = Path('${domain_dir}')
domain_name = '${domain_name}'
entries = []

for md_file in sorted(domain_dir.rglob('*.md')):
    name = md_file.name
    if name.startswith('_') or name == 'context.md' or name.endswith('.stub.md'):
        continue

    # Parse frontmatter
    fields = {}
    body_lines = []
    try:
        with open(md_file, 'r') as f:
            lines = f.readlines()
        if lines and lines[0].strip() == '---':
            count = 0
            past_fm = False
            for line in lines:
                if line.strip() == '---':
                    count += 1
                    if count == 2:
                        past_fm = True
                    continue
                if not past_fm and count == 1:
                    m = re.match(r'^(\w+):\s*(.*)', line.strip())
                    if m:
                        fields[m.group(1)] = m.group(2)
                elif past_fm:
                    body_lines.append(line)
    except:
        pass

    rel = md_file.relative_to(domain_dir)
    title = fields.get('title', name.replace('.md', ''))
    maturity = fields.get('maturity', 'draft')
    importance = fields.get('importance', '0')
    tags = fields.get('tags', '[]')

    # First 100 chars of body as summary
    body = ''.join(body_lines).strip()
    summary = body[:150].replace('\n', ' ').strip()
    if len(body) > 150:
        summary += '...'

    entries.append({
        'path': str(rel),
        'title': title,
        'maturity': maturity,
        'importance': importance,
        'tags': tags,
        'summary': summary,
    })

# Sort by importance descending
entries.sort(key=lambda e: int(e.get('importance', '0')), reverse=True)

# Write _index.md
with open('${index_file}', 'w') as f:
    f.write(f'# {domain_name}\n\n')
    f.write(f'> Auto-generated index. {len(entries)} entries.\n\n')
    for e in entries:
        f.write(f'### {e[\"title\"]}\n')
        f.write(f'- **Path:** {e[\"path\"]}\n')
        f.write(f'- **Maturity:** {e[\"maturity\"]} | **Importance:** {e[\"importance\"]}\n')
        f.write(f'- **Tags:** {e[\"tags\"]}\n')
        if e['summary']:
            f.write(f'- {e[\"summary\"]}\n')
        f.write('\n')
"
  done
}
```

Run test:
```bash
cd /path/to/xgh && bash tests/test-ct-manifest.sh
# Expected: all pass
```

- [x] **Step 3: Run test and verify pass**

```bash
bash tests/test-ct-manifest.sh
```

- [x] **Step 4: Commit**

```bash
git add scripts/ct-manifest.sh tests/test-ct-manifest.sh
git commit -m "Add manifest manager with rebuild, add/remove entries, and index generation"
```

---

## Chunk 5: Archival System

### Task 6: Archive and restore low-importance draft files

**Files:**
- Create: `scripts/ct-archive.sh`
- Create: `tests/test-ct-archive.sh`

- [x] **Step 1: Write failing test for archival**

Create `tests/test-ct-archive.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' — $3"; FAIL=$((FAIL+1)); fi
}
assert_file_exists() {
  if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 missing — $2"; FAIL=$((FAIL+1)); fi
}
assert_file_not_exists() {
  if [ ! -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 should not exist — $2"; FAIL=$((FAIL+1)); fi
}
assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="${REPO_ROOT}/scripts"
source "${SCRIPT_DIR}/ct-frontmatter.sh"
source "${SCRIPT_DIR}/ct-archive.sh"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

CT_DIR="${TMPDIR}/.xgh/context-tree"
mkdir -p "${CT_DIR}/authentication/jwt"
mkdir -p "${CT_DIR}/authentication/oauth"
export XGH_CONTEXT_TREE_DIR="$CT_DIR"

cat > "${CT_DIR}/_manifest.json" <<'EOF'
{"version":1,"team":"test","created":"2026-03-13T00:00:00Z","domains":[]}
EOF

# Create a low-importance draft file (should be archived)
cat > "${CT_DIR}/authentication/jwt/old-token-strategy.md" <<'EOF'
---
title: Old Token Strategy
tags: [auth, jwt]
keywords: [jwt]
importance: 20
recency: 0.1
maturity: draft
accessCount: 1
updateCount: 0
createdAt: 2026-01-01T00:00:00Z
updatedAt: 2026-01-15T00:00:00Z
source: auto-curate
fromAgent: test
---

This is an old strategy that is no longer used.
It has detailed implementation notes here.
EOF

# Create a high-importance file (should NOT be archived)
cat > "${CT_DIR}/authentication/jwt/current-strategy.md" <<'EOF'
---
title: Current JWT Strategy
tags: [auth, jwt]
keywords: [jwt, current]
importance: 80
recency: 0.9
maturity: validated
accessCount: 15
updateCount: 5
createdAt: 2026-02-01T00:00:00Z
updatedAt: 2026-03-10T00:00:00Z
source: manual
fromAgent: test
---

Current active strategy with high importance.
EOF

# Create another low-importance draft (should be archived)
cat > "${CT_DIR}/authentication/oauth/unused-flow.md" <<'EOF'
---
title: Unused OAuth Flow
tags: [auth, oauth]
keywords: [oauth, unused]
importance: 15
recency: 0.05
maturity: draft
accessCount: 0
updateCount: 0
createdAt: 2025-12-01T00:00:00Z
updatedAt: 2025-12-15T00:00:00Z
source: auto-curate
fromAgent: test
---

An OAuth flow that was never used. Contains implementation details.
EOF

# --- Test: archive_stale archives draft files with importance < 35 ---
archive_stale "$CT_DIR" 35

# Old token strategy should be archived
assert_file_not_exists "${CT_DIR}/authentication/jwt/old-token-strategy.md" "original file removed"
assert_file_exists "${CT_DIR}/_archived/authentication/jwt/old-token-strategy.full.md" "full backup exists"
assert_file_exists "${CT_DIR}/authentication/jwt/old-token-strategy.stub.md" "stub exists in original location"

# Stub should have minimal content but be searchable
assert_file_contains "${CT_DIR}/authentication/jwt/old-token-strategy.stub.md" "title: Old Token Strategy" "stub has title"
assert_file_contains "${CT_DIR}/authentication/jwt/old-token-strategy.stub.md" "archived: true" "stub has archived flag"
assert_file_contains "${CT_DIR}/authentication/jwt/old-token-strategy.stub.md" "ARCHIVED" "stub body says ARCHIVED"

# Full backup should have all original content
assert_file_contains "${CT_DIR}/_archived/authentication/jwt/old-token-strategy.full.md" "detailed implementation notes" "full backup has body"

# Current strategy should NOT be archived (high importance)
assert_file_exists "${CT_DIR}/authentication/jwt/current-strategy.md" "high-importance file untouched"

# Unused OAuth flow should be archived
assert_file_not_exists "${CT_DIR}/authentication/oauth/unused-flow.md" "unused flow removed"
assert_file_exists "${CT_DIR}/_archived/authentication/oauth/unused-flow.full.md" "unused flow backup"
assert_file_exists "${CT_DIR}/authentication/oauth/unused-flow.stub.md" "unused flow stub"

# --- Test: restore_archived restores a file from archive ---
restore_archived "$CT_DIR" "authentication/jwt/old-token-strategy"

assert_file_exists "${CT_DIR}/authentication/jwt/old-token-strategy.md" "restored file exists"
assert_file_not_exists "${CT_DIR}/authentication/jwt/old-token-strategy.stub.md" "stub removed after restore"
assert_file_not_exists "${CT_DIR}/_archived/authentication/jwt/old-token-strategy.full.md" "archive backup removed after restore"
assert_file_contains "${CT_DIR}/authentication/jwt/old-token-strategy.md" "detailed implementation notes" "restored content intact"

echo ""
echo "Archive tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

Run to verify failure:
```bash
cd /path/to/xgh && bash tests/test-ct-archive.sh
# Expected: error — ct-archive.sh not found
```

- [x] **Step 2: Implement archival system**

Create `scripts/ct-archive.sh`:

```bash
#!/usr/bin/env bash
# ct-archive.sh — Archive low-importance drafts, restore archived files
# Sourced by context-tree.sh

# archive_single CT_DIR REL_PATH_NO_EXT
# Archives a single file: moves to _archived/.full.md, leaves .stub.md in place.
archive_single() {
  local ct_dir="$1" rel_path="$2"
  local source_file="${ct_dir}/${rel_path}.md"

  if [ ! -f "$source_file" ]; then
    echo "Error: file not found: ${source_file}" >&2
    return 1
  fi

  # Create archive directory
  local archive_dir="${ct_dir}/_archived/$(dirname "$rel_path")"
  mkdir -p "$archive_dir"

  local basename
  basename=$(basename "$rel_path")

  # Copy full file to archive
  cp "$source_file" "${archive_dir}/${basename}.full.md"

  # Create stub in original location
  local stub_file="${ct_dir}/$(dirname "$rel_path")/${basename}.stub.md"

  # Extract frontmatter fields for the stub
  local title tags keywords importance maturity created_at
  title=$(read_frontmatter_field "$source_file" "title")
  tags=$(read_frontmatter_field "$source_file" "tags")
  keywords=$(read_frontmatter_field "$source_file" "keywords")
  importance=$(read_frontmatter_field "$source_file" "importance")
  maturity=$(read_frontmatter_field "$source_file" "maturity")
  created_at=$(read_frontmatter_field "$source_file" "createdAt")

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat > "$stub_file" <<EOF
---
title: ${title}
tags: ${tags}
keywords: ${keywords}
importance: ${importance}
maturity: ${maturity}
archived: true
archivedAt: ${now}
archivePath: _archived/${rel_path}.full.md
createdAt: ${created_at}
updatedAt: ${now}
---

**ARCHIVED** — This entry was archived due to low importance. Use \`context-tree.sh archive --restore "${rel_path}"\` to restore.
EOF

  # Remove original
  rm "$source_file"

  echo "Archived: ${rel_path}"
}

# archive_stale CT_DIR [THRESHOLD]
# Archives all draft files with importance below THRESHOLD (default: 35).
archive_stale() {
  local ct_dir="$1"
  local threshold="${2:-35}"

  find "$ct_dir" -name "*.md" \
    ! -name "_index.md" \
    ! -name "context.md" \
    ! -name "*.stub.md" \
    ! -path "*/_archived/*" \
    -type f | while read -r file; do

    local maturity importance
    maturity=$(read_frontmatter_field "$file" "maturity")
    importance=$(read_frontmatter_field "$file" "importance")
    maturity=${maturity:-draft}
    importance=${importance:-0}

    # Only archive drafts below threshold
    if [ "$maturity" = "draft" ] && [ "$importance" -lt "$threshold" ]; then
      local rel_path="${file#${ct_dir}/}"
      rel_path="${rel_path%.md}"
      archive_single "$ct_dir" "$rel_path"
    fi
  done
}

# restore_archived CT_DIR REL_PATH_NO_EXT
# Restores a file from the archive.
restore_archived() {
  local ct_dir="$1" rel_path="$2"

  local basename
  basename=$(basename "$rel_path")
  local dir_part
  dir_part=$(dirname "$rel_path")

  local archive_file="${ct_dir}/_archived/${dir_part}/${basename}.full.md"
  local stub_file="${ct_dir}/${dir_part}/${basename}.stub.md"
  local target_file="${ct_dir}/${rel_path}.md"

  if [ ! -f "$archive_file" ]; then
    echo "Error: archive not found: ${archive_file}" >&2
    return 1
  fi

  # Ensure target directory exists
  mkdir -p "$(dirname "$target_file")"

  # Restore from archive
  cp "$archive_file" "$target_file"

  # Remove stub and archive
  [ -f "$stub_file" ] && rm "$stub_file"
  rm "$archive_file"

  # Clean up empty archive directories
  local arch_dir
  arch_dir=$(dirname "$archive_file")
  while [ "$arch_dir" != "${ct_dir}/_archived" ] && [ -d "$arch_dir" ]; do
    if [ -z "$(ls -A "$arch_dir" 2>/dev/null)" ]; then
      rmdir "$arch_dir"
      arch_dir=$(dirname "$arch_dir")
    else
      break
    fi
  done

  echo "Restored: ${rel_path}"
}

# cmd_archive [--stale] [--threshold N] [--restore PATH]
cmd_archive() {
  local ct_dir="${XGH_CONTEXT_TREE_DIR:-${PWD}/.xgh/context-tree}"
  local action="stale" threshold=35 restore_path=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --stale)     action="stale"; shift ;;
      --threshold) threshold="$2"; shift 2 ;;
      --restore)   action="restore"; restore_path="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
  done

  case "$action" in
    stale)   archive_stale "$ct_dir" "$threshold" ;;
    restore) restore_archived "$ct_dir" "$restore_path" ;;
  esac
}
```

Run test:
```bash
cd /path/to/xgh && bash tests/test-ct-archive.sh
# Expected: all pass
```

- [x] **Step 3: Run test and verify pass**

```bash
bash tests/test-ct-archive.sh
```

- [x] **Step 4: Commit**

```bash
git add scripts/ct-archive.sh tests/test-ct-archive.sh
git commit -m "Add archival system for low-importance draft files with stub preservation"
```

---

## Chunk 6: Sync Dispatcher

### Task 7: Sync dispatcher — curate and query orchestration

**Files:**
- Create: `scripts/ct-sync.sh`
- Create: `tests/test-ct-sync.sh`

- [x] **Step 1: Write failing test for sync operations**

Create `tests/test-ct-sync.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' — $3"; FAIL=$((FAIL+1)); fi
}
assert_file_exists() {
  if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 missing — $2"; FAIL=$((FAIL+1)); fi
}
assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}
assert_contains() {
  if echo "$1" | grep -q "$2" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: output missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CT_SCRIPT="${REPO_ROOT}/scripts/context-tree.sh"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

CT_DIR="${TMPDIR}/.xgh/context-tree"
mkdir -p "$CT_DIR"
cat > "${CT_DIR}/_manifest.json" <<'EOF'
{"version":1,"team":"test","created":"2026-03-13T00:00:00Z","domains":[]}
EOF

export XGH_CONTEXT_TREE_DIR="$CT_DIR"

# --- Test: sync curate — creates file + updates manifest + generates index ---
bash "$CT_SCRIPT" sync --action curate \
  --domain "authentication" \
  --topic "jwt" \
  --title "JWT Best Practices" \
  --tags "auth,jwt,security" \
  --keywords "jwt,best-practices" \
  --source "auto-curate" \
  --from-agent "claude-code" \
  --body "## Raw Concept
Always validate JWT signature before trusting claims.

## Facts
- category: convention
  fact: Validate JWT signature server-side, never trust client-decoded tokens"

EXPECTED="${CT_DIR}/authentication/jwt/jwt-best-practices.md"
assert_file_exists "$EXPECTED" "curate created knowledge file"
assert_file_contains "$EXPECTED" "importance: 10" "initial importance from curate"

# Manifest should be updated
MANIFEST=$(cat "${CT_DIR}/_manifest.json")
assert_contains "$MANIFEST" "jwt-best-practices" "manifest updated by curate"
assert_contains "$MANIFEST" "authentication" "manifest has domain"

# Index should be generated
assert_file_exists "${CT_DIR}/authentication/_index.md" "index generated by curate"
assert_file_contains "${CT_DIR}/authentication/_index.md" "JWT Best Practices" "index has title"

# --- Test: sync curate with manual source gives +10 importance ---
bash "$CT_SCRIPT" sync --action curate \
  --domain "api-design" \
  --topic "rest" \
  --title "REST Naming" \
  --tags "api" \
  --keywords "rest,naming" \
  --source "manual" \
  --from-agent "test" \
  --body "Use kebab-case."

MANUAL_FILE="${CT_DIR}/api-design/rest/rest-naming.md"
assert_file_exists "$MANUAL_FILE" "manual curate file created"
# Manual curate: base 10 + 10 manual bonus = 20
assert_file_contains "$MANUAL_FILE" "importance: 20" "manual curate importance boost"

# --- Test: sync query — searches and returns results ---
QUERY_RESULT=$(bash "$CT_SCRIPT" sync --action query --query "JWT token validation")
assert_contains "$QUERY_RESULT" "jwt-best-practices" "query found JWT file"

# --- Test: sync score — runs scoring pass on all files ---
bash "$CT_SCRIPT" sync --action score
# Files should still have valid frontmatter
assert_file_contains "$EXPECTED" "title:" "scoring preserved frontmatter"

# --- Test: sync archive — archives stale drafts ---
# Create a low-importance file
bash "$CT_SCRIPT" create \
  --domain "testing" --topic "old" \
  --title "Old Test Approach" --tags "test" --keywords "old" \
  --source "auto-curate" --from-agent "test" --body "Outdated approach."

# Manually set importance to very low
OLD_FILE="${CT_DIR}/testing/old/old-test-approach.md"
sed -i '' 's/importance: 10/importance: 5/' "$OLD_FILE" 2>/dev/null || \
  sed -i 's/importance: 10/importance: 5/' "$OLD_FILE"

bash "$CT_SCRIPT" sync --action archive
assert_file_exists "${CT_DIR}/testing/old/old-test-approach.stub.md" "stale file archived by sync"

echo ""
echo "Sync tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

Run to verify failure:
```bash
cd /path/to/xgh && bash tests/test-ct-sync.sh
# Expected: error — ct-sync.sh not found or cmd_sync missing
```

- [x] **Step 2: Implement sync dispatcher**

Create `scripts/ct-sync.sh`:

```bash
#!/usr/bin/env bash
# ct-sync.sh — Sync dispatcher: curate, query, score, archive orchestration
# Sourced by context-tree.sh

# Ensure dependencies are loaded
SCRIPT_DIR_SYNC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies if not already loaded
type read_frontmatter_field &>/dev/null || source "${SCRIPT_DIR_SYNC}/ct-frontmatter.sh"
type rebuild_manifest &>/dev/null || source "${SCRIPT_DIR_SYNC}/ct-manifest.sh"
type cmd_score &>/dev/null || source "${SCRIPT_DIR_SYNC}/ct-scoring.sh"
type archive_stale &>/dev/null || source "${SCRIPT_DIR_SYNC}/ct-archive.sh"
type cmd_search &>/dev/null || source "${SCRIPT_DIR_SYNC}/ct-search.sh"

# cmd_sync --action curate|query|score|archive [options]
cmd_sync() {
  local action=""
  local domain="" topic="" subtopic="" title="" tags="" keywords=""
  local source_val="auto-curate" from_agent="" body="" related=""
  local query="" limit=10 cipher_results=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --action)         action="$2"; shift 2 ;;
      --domain)         domain="$2"; shift 2 ;;
      --topic)          topic="$2"; shift 2 ;;
      --subtopic)       subtopic="$2"; shift 2 ;;
      --title)          title="$2"; shift 2 ;;
      --tags)           tags="$2"; shift 2 ;;
      --keywords)       keywords="$2"; shift 2 ;;
      --source)         source_val="$2"; shift 2 ;;
      --from-agent)     from_agent="$2"; shift 2 ;;
      --body)           body="$2"; shift 2 ;;
      --related)        related="$2"; shift 2 ;;
      --query)          query="$2"; shift 2 ;;
      --limit)          limit="$2"; shift 2 ;;
      --cipher-results) cipher_results="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "$action" ]; then
    echo "Error: --action is required (curate|query|score|archive)" >&2
    return 1
  fi

  local ct_dir="${XGH_CONTEXT_TREE_DIR:-${PWD}/.xgh/context-tree}"

  case "$action" in
    curate)
      _sync_curate "$ct_dir" "$domain" "$topic" "$subtopic" "$title" \
        "$tags" "$keywords" "$source_val" "$from_agent" "$body" "$related"
      ;;
    query)
      _sync_query "$ct_dir" "$query" "$limit" "$cipher_results"
      ;;
    score)
      cmd_score --all
      ;;
    archive)
      archive_stale "$ct_dir" 35
      ;;
    *)
      echo "Error: unknown action '$action'" >&2
      return 1
      ;;
  esac
}

_sync_curate() {
  local ct_dir="$1" domain="$2" topic="$3" subtopic="$4" title="$5"
  local tags="$6" keywords="$7" source_val="$8" from_agent="$9" body="${10}" related="${11}"

  if [ -z "$domain" ] || [ -z "$title" ]; then
    echo "Error: --domain and --title required for curate" >&2
    return 1
  fi

  # Step 1: Create the knowledge file via context-tree.sh create
  local ct_script="${SCRIPT_DIR_SYNC}/context-tree.sh"
  local create_args=(
    create
    --domain "$domain"
    --title "$title"
    --tags "$tags"
    --keywords "$keywords"
    --source "$source_val"
    --from-agent "$from_agent"
    --body "$body"
  )
  [ -n "$topic" ] && create_args+=(--topic "$topic")
  [ -n "$subtopic" ] && create_args+=(--subtopic "$subtopic")
  [ -n "$related" ] && create_args+=(--related "$related")

  bash "$ct_script" "${create_args[@]}"

  # Step 2: If manual curate, bump importance by +10
  if [ "$source_val" = "manual" ]; then
    local title_slug
    title_slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
    local dir_path="${ct_dir}/${domain}"
    [ -n "$topic" ] && dir_path="${dir_path}/${topic}"
    [ -n "$subtopic" ] && dir_path="${dir_path}/${subtopic}"
    local file_path="${dir_path}/${title_slug}.md"

    if [ -f "$file_path" ]; then
      local imp
      imp=$(read_frontmatter_field "$file_path" "importance")
      imp=${imp:-0}
      local new_imp=$((imp + 10))
      [ "$new_imp" -gt 100 ] && new_imp=100
      update_frontmatter_field "$file_path" "importance" "$new_imp"
    fi
  fi

  # Step 3: Update manifest
  local title_slug
  title_slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
  local rel_path="${domain}"
  [ -n "$topic" ] && rel_path="${rel_path}/${topic}"
  [ -n "$subtopic" ] && rel_path="${rel_path}/${subtopic}"
  rel_path="${rel_path}/${title_slug}.md"

  local file_path="${ct_dir}/${rel_path}"
  local importance="10"
  if [ -f "$file_path" ]; then
    importance=$(read_frontmatter_field "$file_path" "importance")
  fi

  add_to_manifest "$ct_dir" "$rel_path" "$title" "draft" "$importance"

  # Step 4: Generate index for the domain
  generate_index "$ct_dir"

  echo "Curated: ${rel_path}"
}

_sync_query() {
  local ct_dir="$1" query="$2" limit="$3" cipher_results="$4"

  if [ -z "$query" ]; then
    echo "Error: --query required for query action" >&2
    return 1
  fi

  local search_args=(--query "$query" --limit "$limit")
  [ -n "$cipher_results" ] && search_args+=(--cipher-results "$cipher_results")

  cmd_search "${search_args[@]}"
}
```

Run test:
```bash
cd /path/to/xgh && bash tests/test-ct-sync.sh
# Expected: all pass
```

- [x] **Step 3: Run test and verify pass**

```bash
bash tests/test-ct-sync.sh
```

- [x] **Step 4: Commit**

```bash
git add scripts/ct-sync.sh tests/test-ct-sync.sh
git commit -m "Add sync dispatcher for curate/query/score/archive orchestration"
```

---

## Chunk 7: Integration Test + Make Scripts Executable

### Task 8: Full integration test and cleanup

**Files:**
- Create: `tests/test-ct-integration.sh`
- Modify: all scripts (ensure executable bit)

- [x] **Step 1: Write integration test that exercises the full workflow**

Create `tests/test-ct-integration.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' — $3"; FAIL=$((FAIL+1)); fi
}
assert_file_exists() {
  if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 missing — $2"; FAIL=$((FAIL+1)); fi
}
assert_file_not_exists() {
  if [ ! -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 should not exist — $2"; FAIL=$((FAIL+1)); fi
}
assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}
assert_contains() {
  if echo "$1" | grep -q "$2" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: output missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CT_SCRIPT="${REPO_ROOT}/scripts/context-tree.sh"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# --- Setup: Initialize context tree from scratch ---
CT_DIR="${TMPDIR}/.xgh/context-tree"
mkdir -p "$CT_DIR"
cat > "${CT_DIR}/_manifest.json" <<'EOF'
{"version":1,"team":"integration-test","created":"2026-03-13T00:00:00Z","domains":[]}
EOF
export XGH_CONTEXT_TREE_DIR="$CT_DIR"

echo "=== Phase 1: Curate multiple knowledge files ==="

bash "$CT_SCRIPT" sync --action curate \
  --domain "backend" --topic "database" \
  --title "PostgreSQL Connection Pooling" \
  --tags "database,postgres,performance" \
  --keywords "connection-pool,pgbouncer" \
  --source "manual" --from-agent "claude-code" \
  --body "## Raw Concept
Use PgBouncer for connection pooling. Set pool_mode to transaction.
Max connections per pool: 20 for web servers, 5 for background workers.

## Facts
- category: convention
  fact: Always use PgBouncer, never direct connections in production"

bash "$CT_SCRIPT" sync --action curate \
  --domain "backend" --topic "database" \
  --title "Database Migration Strategy" \
  --tags "database,migrations" \
  --keywords "migrations,schema,versioning" \
  --source "auto-curate" --from-agent "claude-code" \
  --body "## Raw Concept
Use sequential migration files. Never modify existing migrations.
Always test rollback before deploying."

bash "$CT_SCRIPT" sync --action curate \
  --domain "frontend" --topic "react" \
  --title "React State Management" \
  --tags "frontend,react,state" \
  --keywords "state,zustand,context" \
  --source "manual" --from-agent "claude-code" \
  --body "## Raw Concept
Use Zustand for global state. React Context for theme/locale only.
Never put server cache in Zustand — use React Query instead."

bash "$CT_SCRIPT" sync --action curate \
  --domain "devops" --topic "ci-cd" \
  --title "CI Pipeline Conventions" \
  --tags "devops,ci,github-actions" \
  --keywords "ci,pipeline,github-actions" \
  --source "auto-curate" --from-agent "claude-code" \
  --body "Run lint, test, build in parallel. Deploy only from main branch."

# Verify files created
assert_file_exists "${CT_DIR}/backend/database/postgresql-connection-pooling.md" "postgres file"
assert_file_exists "${CT_DIR}/backend/database/database-migration-strategy.md" "migration file"
assert_file_exists "${CT_DIR}/frontend/react/react-state-management.md" "react file"
assert_file_exists "${CT_DIR}/devops/ci-cd/ci-pipeline-conventions.md" "ci file"

echo "=== Phase 2: Verify manifest and indexes ==="

# Manifest should have all domains
MANIFEST=$(cat "${CT_DIR}/_manifest.json")
assert_contains "$MANIFEST" "backend" "manifest has backend"
assert_contains "$MANIFEST" "frontend" "manifest has frontend"
assert_contains "$MANIFEST" "devops" "manifest has devops"

# Indexes should exist
assert_file_exists "${CT_DIR}/backend/_index.md" "backend index"
assert_file_exists "${CT_DIR}/frontend/_index.md" "frontend index"
assert_file_exists "${CT_DIR}/devops/_index.md" "devops index"

echo "=== Phase 3: Search ==="

# Search for database topics
RESULT=$(bash "$CT_SCRIPT" search --query "PostgreSQL connection pooling PgBouncer")
assert_contains "$RESULT" "postgresql-connection-pooling" "search finds postgres file"

# Search for React
RESULT2=$(bash "$CT_SCRIPT" search --query "React state management Zustand")
assert_contains "$RESULT2" "react-state-management" "search finds react file"

echo "=== Phase 4: Read + importance bumps ==="

# Read a file (bumps accessCount and importance)
bash "$CT_SCRIPT" read --path "backend/database/postgresql-connection-pooling" > /dev/null
bash "$CT_SCRIPT" read --path "backend/database/postgresql-connection-pooling" > /dev/null
bash "$CT_SCRIPT" read --path "backend/database/postgresql-connection-pooling" > /dev/null

# Check importance bumped: manual curate (20) + 3 reads * 3 = 29
PG_FILE="${CT_DIR}/backend/database/postgresql-connection-pooling.md"
IMP=$(grep "^importance:" "$PG_FILE" | head -1 | awk '{print $2}')
assert_eq "$IMP" "29" "importance after manual curate + 3 reads"

ACCESS=$(grep "^accessCount:" "$PG_FILE" | head -1 | awk '{print $2}')
assert_eq "$ACCESS" "3" "accessCount after 3 reads"

echo "=== Phase 5: Update ==="

bash "$CT_SCRIPT" update \
  --path "backend/database/postgresql-connection-pooling" \
  --body "## Raw Concept
Use PgBouncer for connection pooling. Set pool_mode to transaction.
Max connections: 20 for web, 5 for workers. Updated: Add health checks.

## Facts
- category: convention
  fact: Always use PgBouncer with health check endpoint"

# importance: 29 + 5 (update) = 34
IMP2=$(grep "^importance:" "$PG_FILE" | head -1 | awk '{print $2}')
assert_eq "$IMP2" "34" "importance after update"

echo "=== Phase 6: Scoring + maturity promotion ==="

# Manually set importance high enough for promotion
sed -i '' 's/importance: 34/importance: 65/' "$PG_FILE" 2>/dev/null || \
  sed -i 's/importance: 34/importance: 65/' "$PG_FILE"

bash "$CT_SCRIPT" sync --action score
MAT=$(grep "^maturity:" "$PG_FILE" | head -1 | awk '{print $2}')
assert_eq "$MAT" "validated" "promoted to validated at importance 65"

echo "=== Phase 7: Archive ==="

# CI file has low importance (auto-curate = 10), should be archived
CI_FILE="${CT_DIR}/devops/ci-cd/ci-pipeline-conventions.md"
CI_IMP=$(grep "^importance:" "$CI_FILE" | head -1 | awk '{print $2}')
echo "CI importance before archive: $CI_IMP"

# Set to very low for archival test
sed -i '' 's/importance: 10/importance: 5/' "$CI_FILE" 2>/dev/null || \
  sed -i 's/importance: 10/importance: 5/' "$CI_FILE"

bash "$CT_SCRIPT" sync --action archive
assert_file_not_exists "$CI_FILE" "CI file archived"
assert_file_exists "${CT_DIR}/devops/ci-cd/ci-pipeline-conventions.stub.md" "CI stub exists"
assert_file_exists "${CT_DIR}/_archived/devops/ci-cd/ci-pipeline-conventions.full.md" "CI full backup"

# Restore it
bash "$CT_SCRIPT" archive --restore "devops/ci-cd/ci-pipeline-conventions"
assert_file_exists "$CI_FILE" "CI file restored"

echo "=== Phase 8: List ==="

LIST=$(bash "$CT_SCRIPT" list)
assert_contains "$LIST" "postgresql-connection-pooling" "list shows postgres"
assert_contains "$LIST" "database-migration-strategy" "list shows migration"
assert_contains "$LIST" "react-state-management" "list shows react"

# List with domain filter
LIST_BE=$(bash "$CT_SCRIPT" list --domain "backend")
assert_contains "$LIST_BE" "postgresql" "filtered list has postgres"

echo "=== Phase 9: Delete ==="

bash "$CT_SCRIPT" delete --path "backend/database/database-migration-strategy"
assert_file_not_exists "${CT_DIR}/backend/database/database-migration-strategy.md" "deleted migration file"

echo ""
echo "=== Integration test: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
```

- [x] **Step 2: Make all scripts executable**

```bash
chmod +x scripts/context-tree.sh scripts/ct-frontmatter.sh scripts/ct-scoring.sh \
  scripts/ct-search.sh scripts/ct-manifest.sh scripts/ct-archive.sh scripts/ct-sync.sh \
  scripts/bm25.py
chmod +x tests/test-ct-crud.sh tests/test-ct-frontmatter.sh tests/test-ct-scoring.sh \
  tests/test-ct-search.sh tests/test-ct-manifest.sh tests/test-ct-archive.sh \
  tests/test-ct-sync.sh tests/test-ct-integration.sh
```

- [x] **Step 3: Run integration test**

```bash
cd /path/to/xgh && bash tests/test-ct-integration.sh
# Expected: all pass
```

- [x] **Step 4: Run all context tree tests to confirm nothing is broken**

```bash
cd /path/to/xgh
for t in tests/test-ct-*.sh; do
  echo "--- Running $t ---"
  bash "$t" || { echo "FAILED: $t"; exit 1; }
  echo ""
done
echo "All context tree tests passed."
```

- [x] **Step 5: Commit**

```bash
git add scripts/ tests/test-ct-integration.sh
git commit -m "Add integration test and make all context tree scripts executable"
```

---

## Summary of all files created

| File | Purpose |
|------|---------|
| `scripts/context-tree.sh` | Main dispatcher — create/read/update/delete/list + routes to sub-scripts |
| `scripts/ct-frontmatter.sh` | YAML frontmatter parse/write/update helpers |
| `scripts/ct-scoring.sh` | Importance bumps, recency decay (21-day half-life), maturity promotion with hysteresis |
| `scripts/ct-search.sh` | BM25 search wrapper + Cipher result merge (combined scoring formula) |
| `scripts/bm25.py` | Python BM25/TF-IDF search engine over markdown files |
| `scripts/ct-manifest.sh` | Manifest rebuild/add/remove + domain `_index.md` generation |
| `scripts/ct-archive.sh` | Archive stale drafts to `.stub.md` + `.full.md`, restore from archive |
| `scripts/ct-sync.sh` | Sync dispatcher: curate (create+manifest+index), query (BM25+merge), score, archive |
| `tests/test-ct-frontmatter.sh` | Frontmatter parse/write tests |
| `tests/test-ct-crud.sh` | Knowledge file CRUD tests |
| `tests/test-ct-scoring.sh` | Scoring + maturity tests |
| `tests/test-ct-search.sh` | BM25 search tests |
| `tests/test-ct-manifest.sh` | Manifest + index tests |
| `tests/test-ct-archive.sh` | Archival tests |
| `tests/test-ct-sync.sh` | Sync dispatcher tests |
| `tests/test-ct-integration.sh` | Full end-to-end integration test |
