#!/usr/bin/env bash
# write-inbox-item.sh — Deduplicating inbox write helper
#
# Usage:
#   echo "<content>" | write-inbox-item.sh <filename> [inbox_dir]
#
# Writes a new inbox item only if no duplicate already exists.
# Dedup strategy (in priority order):
#   1. source_repo + source_type + item number extracted from filename
#      (e.g. pr104, issue823) — logical identity dedup
#   2. Content hash (sha256) — exact-match fallback when identifier
#      cannot be parsed from filename
#
# Env vars (all optional — defaults work for standard installs):
#   INBOX_DIR   — path to inbox directory (default: ~/.xgh/inbox)
#   LOG_FILE    — path to retriever log (default: ~/.xgh/logs/retriever.log)
#
# Exit codes:
#   0 — item written (new) or skipped (duplicate)
#   1 — usage error (no filename provided)
#
# The script is designed to be called from provider fetch.sh scripts but
# also works standalone for testing.

set -euo pipefail

INBOX_DIR="${INBOX_DIR:-$HOME/.xgh/inbox}"
LOG_FILE="${LOG_FILE:-$HOME/.xgh/logs/retriever.log}"

# ── Argument validation ───────────────────────────────────────────────────────
if [ $# -lt 1 ]; then
    echo "Usage: write-inbox-item.sh <filename> [inbox_dir]" >&2
    exit 1
fi

FILENAME="$1"
# Allow caller to override inbox dir as second positional arg (useful in tests)
if [ $# -ge 2 ]; then
    INBOX_DIR="$2"
fi

DEST="$INBOX_DIR/$FILENAME"
mkdir -p "$INBOX_DIR" "$(dirname "$LOG_FILE")"

# ── Read content from stdin ───────────────────────────────────────────────────
CONTENT=$(cat)

# ── Early exit: exact filename already exists ─────────────────────────────────
# This is the cheapest possible dedup check — if the exact output file already
# exists we never overwrite it (first write wins, consistent with fetch.sh).
if [ -f "$DEST" ]; then
    exit 0
fi

# ── Dedup helper: extract item identifier from filename ───────────────────────
# Filename pattern: <ts>_github_<owner>_<repo>_<type><number>.md
# e.g. 2026-03-26T18-10-11Z_github_rtk-ai_rtk_issue823.md
#      2026-03-26T19-06-05Z_github_Martian-Engineering_lossless-claw_pr153.md
#
# We extract: source_repo (owner/repo from yaml) + item type + number
# and search for any existing inbox file whose YAML frontmatter matches
# the same source_repo + source_type combination with the same number.
#
# Fallback: sha256 content hash when the filename doesn't match expected pattern.

_basename="${FILENAME%.md}"

# Try to extract logical identifier from filename
# Pattern: <ts>Z_github_<owner>_<repo>_<typekind><number>
# The type+number suffix is the last segment after the final underscore
_suffix="${_basename##*_}"      # e.g. issue823, pr153, release_v1.2.0

# Determine if suffix looks like a numbered item (issue/pr + digits)
_item_number=""
_item_kind=""
if [[ "$_suffix" =~ ^(issue|pr)([0-9]+)$ ]]; then
    _item_kind="${BASH_REMATCH[1]}"
    _item_number="${BASH_REMATCH[2]}"
fi

# ── Strategy 1: logical identity dedup (source_repo + type + number) ─────────
if [ -n "$_item_number" ]; then
    # Extract source_repo from the content being written (it's in frontmatter)
    _source_repo=$(printf '%s' "$CONTENT" | { grep "^source_repo:" || true; } | head -1 | awk '{print $2}')
    _source_type_prefix="github_${_item_kind}"

    if [ -n "$_source_repo" ]; then
        # Search existing inbox files for same source_repo + source_type + number
        # Use python3 for reliable YAML frontmatter parsing
        _duplicate=$(python3 - "$INBOX_DIR" "$_source_repo" "$_source_type_prefix" "$_item_number" << 'PYDEDUP'
import os, sys, re

inbox_dir   = sys.argv[1]
source_repo = sys.argv[2]
type_prefix = sys.argv[3]   # e.g. "github_pr"
item_number = sys.argv[4]   # e.g. "153"

# Build regex to match the source_type line (github_pr or github_issue)
type_re = re.compile(r'^source_type:\s*' + re.escape(type_prefix) + r'\s*$', re.MULTILINE)
repo_re = re.compile(r'^source_repo:\s*' + re.escape(source_repo) + r'\s*$', re.MULTILINE)

# Also check filename for the number as a quick pre-filter
num_suffix = f"_{type_prefix.replace('github_', '')}{item_number}.md"

if not os.path.isdir(inbox_dir):
    print("")
    sys.exit(0)

for fname in os.listdir(inbox_dir):
    if not fname.endswith('.md'):
        continue
    if fname.startswith('WARN_'):
        continue
    # Quick pre-filter: filename must end with <kind><number>.md
    if not fname.endswith(num_suffix):
        continue
    fpath = os.path.join(inbox_dir, fname)
    try:
        with open(fpath, encoding='utf-8', errors='replace') as f:
            content = f.read(2000)  # Only read frontmatter region
        if repo_re.search(content) and type_re.search(content):
            print(fname)
            sys.exit(0)
    except OSError:
        continue

print("")
PYDEDUP
)
        if [ -n "$_duplicate" ]; then
            echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) write-inbox-item: SKIP $FILENAME — duplicate of $_duplicate (source_repo+type+number match)" >> "$LOG_FILE"
            exit 0
        fi
    fi
fi

# ── Strategy 2: content-hash dedup ────────────────────────────────────────────
# Compute sha256 of the content we're about to write.
# Compare against a hash sidecar file stored alongside each inbox item.
# Sidecar: <inbox_dir>/.hashes/<filename>.sha256
HASH_DIR="$INBOX_DIR/.hashes"
mkdir -p "$HASH_DIR"

if command -v sha256sum &>/dev/null; then
    _content_hash=$(printf '%s' "$CONTENT" | sha256sum | awk '{print $1}')
elif command -v shasum &>/dev/null; then
    _content_hash=$(printf '%s' "$CONTENT" | shasum -a 256 | awk '{print $1}')
else
    # No hash tool available — skip hash dedup, proceed to write
    _content_hash=""
fi

if [ -n "$_content_hash" ]; then
    # Check if any existing hash sidecar matches this content hash
    _hash_match=$(grep -rl "$_content_hash" "$HASH_DIR" 2>/dev/null | head -1 || true)
    if [ -n "$_hash_match" ]; then
        _matched_item=$(basename "$_hash_match" .sha256)
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) write-inbox-item: SKIP $FILENAME — duplicate content hash of $_matched_item" >> "$LOG_FILE"
        exit 0
    fi
fi

# ── Write item ────────────────────────────────────────────────────────────────
printf '%s' "$CONTENT" > "$DEST"

# Store content hash sidecar for future dedup checks
if [ -n "$_content_hash" ]; then
    printf '%s' "$_content_hash" > "$HASH_DIR/$FILENAME.sha256"
fi

exit 0
