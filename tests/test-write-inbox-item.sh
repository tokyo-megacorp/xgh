#!/usr/bin/env bash
# test-write-inbox-item.sh — Tests for scripts/write-inbox-item.sh
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS+1))
    else
        echo "FAIL [$desc]: expected='$expected' actual='$actual'"
        FAIL=$((FAIL+1))
    fi
}

assert_file_exists() {
    local desc="$1" path="$2"
    if [ -f "$path" ]; then PASS=$((PASS+1)); else
        echo "FAIL [$desc]: file not found: $path"
        FAIL=$((FAIL+1))
    fi
}

assert_file_absent() {
    local desc="$1" path="$2"
    if [ ! -f "$path" ]; then PASS=$((PASS+1)); else
        echo "FAIL [$desc]: file should not exist: $path"
        FAIL=$((FAIL+1))
    fi
}

assert_log_contains() {
    local desc="$1" pattern="$2" log="$3"
    if grep -q "$pattern" "$log" 2>/dev/null; then PASS=$((PASS+1)); else
        echo "FAIL [$desc]: log does not contain '$pattern' in $log"
        FAIL=$((FAIL+1))
    fi
}

SCRIPT="scripts/write-inbox-item.sh"

# ── Sanity: script exists and is executable ───────────────────────────────────
if [ -x "$SCRIPT" ]; then PASS=$((PASS+1)); else
    echo "FAIL: $SCRIPT not found or not executable"
    FAIL=$((FAIL+1))
fi

# ── Set up temp workspace ─────────────────────────────────────────────────────
TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

INBOX="$TMPDIR_WORK/inbox"
LOGF="$TMPDIR_WORK/test.log"
mkdir -p "$INBOX"

run_helper() {
    # Usage: run_helper <filename> <content>
    INBOX_DIR="$INBOX" LOG_FILE="$LOGF" \
        bash "$SCRIPT" "$1" "$INBOX" <<< "$2"
}

# ── Sample YAML frontmatter builder ──────────────────────────────────────────
make_content() {
    local source_type="$1" source_repo="$2" number="$3" title="$4"
    printf -- "---\ntype: inbox_item\nsource_type: %s\nsource_repo: %s\nsource_ts: 2026-03-26T18:10:11Z\nproject: test\nurgency_score: 50\nprocessed: false\nawaiting_direction: null\nlinks_followed: []\n---\n\n%s #%s: %s\n" \
        "$source_type" "$source_repo" "$number" "$title"
}

# ── Test 1: Write new item (no existing file) ─────────────────────────────────
FNAME1="2026-03-26T18-10-11Z_github_rtk-ai_rtk_issue823.md"
CONTENT1=$(make_content "github_issue" "rtk-ai/rtk" "823" "issue" "feat: new thing")
run_helper "$FNAME1" "$CONTENT1"
assert_file_exists "write new item" "$INBOX/$FNAME1"

# ── Test 2: Same filename written twice — skip second write ───────────────────
CONTENT1_B="different content but same file"
run_helper "$FNAME1" "$CONTENT1_B"
# Content of file should still be original (first write wins)
_actual=$(cat "$INBOX/$FNAME1")
assert_eq "same filename not overwritten" "$CONTENT1" "$_actual"

# ── Test 3: Different timestamp but same source_repo+type+number → skip ───────
# Simulates the re-fetch-after-update scenario (the main bug)
FNAME3="2026-03-26T19-00-00Z_github_rtk-ai_rtk_issue823.md"
CONTENT3=$(make_content "github_issue" "rtk-ai/rtk" "823" "issue" "feat: new thing (updated)")
run_helper "$FNAME3" "$CONTENT3"
assert_file_absent "dedup by logical identity blocks re-fetch" "$INBOX/$FNAME3"
assert_log_contains "log records skip" "SKIP $FNAME3" "$LOGF"

# ── Test 4: Different repo, same type+number — must NOT be deduped ────────────
FNAME4="2026-03-26T18-10-11Z_github_other-org_other-repo_issue823.md"
CONTENT4=$(make_content "github_issue" "other-org/other-repo" "823" "issue" "different repo same number")
run_helper "$FNAME4" "$CONTENT4"
assert_file_exists "different repo same number is NOT deduped" "$INBOX/$FNAME4"

# ── Test 5: Different type (pr vs issue), same repo+number — must NOT dedup ───
FNAME5="2026-03-26T18-10-11Z_github_rtk-ai_rtk_pr823.md"
CONTENT5=$(make_content "github_pr" "rtk-ai/rtk" "823" "pr" "a pull request")
run_helper "$FNAME5" "$CONTENT5"
assert_file_exists "pr with same number as issue is NOT deduped" "$INBOX/$FNAME5"

# ── Test 6: Content-hash dedup — same content, novel filename/repo ────────────
# Use a filename that doesn't match the number pattern so Strategy 1 is skipped
FNAME6A="2026-03-26T18-10-11Z_github_org_repo_release_v1.0.md"
CONTENT6=$(cat <<'EOF'
---
type: inbox_item
source_type: github_release
source_repo: org/repo
---
Release v1.0
EOF
)
run_helper "$FNAME6A" "$CONTENT6"
assert_file_exists "first release item written" "$INBOX/$FNAME6A"

FNAME6B="2026-03-26T19-00-00Z_github_org_repo_release_v1.0.md"
run_helper "$FNAME6B" "$CONTENT6"
# Same content — content-hash dedup should block the second write
assert_file_absent "content-hash dedup blocks identical release re-fetch" "$INBOX/$FNAME6B"
assert_log_contains "log records hash dedup skip" "SKIP $FNAME6B" "$LOGF"

# ── Test 7: Hash sidecar file is created (repo-scoped naming: <repo_slug>_<hash>.sha256) ─────────
_sidecar_count=$(ls "$INBOX/.hashes/org_repo_"*.sha256 2>/dev/null | wc -l | tr -d ' ')
assert_eq "hash sidecar created (repo-scoped)" "1" "$_sidecar_count"

# ── Test 8: PR item — end-to-end write and dedup ─────────────────────────────
FNAME8A="2026-03-26T17-06-00Z_github_Martian-Engineering_lossless-claw_pr104.md"
CONTENT8=$(make_content "github_pr" "Martian-Engineering/lossless-claw" "104" "pr" "first fetch")
run_helper "$FNAME8A" "$CONTENT8"
assert_file_exists "pr104 first fetch written" "$INBOX/$FNAME8A"

FNAME8B="2026-03-26T17-07-00Z_github_Martian-Engineering_lossless-claw_pr104.md"
CONTENT8B=$(make_content "github_pr" "Martian-Engineering/lossless-claw" "104" "pr" "second fetch after update")
run_helper "$FNAME8B" "$CONTENT8B"
assert_file_absent "pr104 re-fetch blocked by logical dedup" "$INBOX/$FNAME8B"
assert_log_contains "log records pr104 dedup" "SKIP $FNAME8B" "$LOGF"

# ── Test 9: Usage error — no filename ────────────────────────────────────────
set +e
bash "$SCRIPT" 2>/dev/null
_rc=$?
set -e
assert_eq "no args exits 1" "1" "$_rc"

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
