#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }
assert_executable() { if [ -x "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 not executable"; FAIL=$((FAIL+1)); fi; }

assert_file_exists "scripts/retrieve-all.sh"
assert_executable "scripts/retrieve-all.sh"
assert_contains "scripts/retrieve-all.sh" "#!/usr/bin/env bash"
assert_contains "scripts/retrieve-all.sh" "set -euo pipefail"
assert_contains "scripts/retrieve-all.sh" "providers"
assert_contains "scripts/retrieve-all.sh" "fetch.sh"
assert_contains "scripts/retrieve-all.sh" "cursor"
assert_contains "scripts/retrieve-all.sh" "retriever.log"

assert_contains "scripts/retrieve-all.sh" "XGH_PROJECT_SCOPE"

assert_contains "scripts/retrieve-all.sh" "user_providers"
assert_contains "scripts/retrieve-all.sh" "PROVIDER_DIR"
assert_contains "scripts/retrieve-all.sh" "CURSOR_FILE"
assert_contains "scripts/retrieve-all.sh" "TOKENS_FILE"
assert_contains "scripts/retrieve-all.sh" "mode: cli"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
