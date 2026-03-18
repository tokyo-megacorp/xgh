#!/usr/bin/env bash
# tests/test-ingest-foundation.sh
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }

assert_file_exists "lib/workspace-write.js"
assert_contains "lib/workspace-write.js" "xgh_schema_version"
assert_contains "lib/workspace-write.js" "cipher.yml"
assert_contains "lib/workspace-write.js" "dry-run"

assert_file_exists "lib/config-reader.sh"
assert_file_exists "lib/usage-tracker.sh"
assert_contains "lib/config-reader.sh" "xgh_config_get"
assert_contains "lib/usage-tracker.sh" "xgh_usage_log"
assert_contains "lib/usage-tracker.sh" "xgh_usage_check_cap"

# Functional test: config reader
_HOME_BAK="$HOME"; export HOME
HOME="$(mktemp -d)"
mkdir -p "$HOME/.xgh"
cat > "$HOME/.xgh/ingest.yaml" << 'YAMLEOF'
budget:
  daily_token_cap: 500000
  warn_at_percent: 80
YAMLEOF
# shellcheck source=/dev/null
source lib/config-reader.sh
_cap=$(xgh_config_get "budget.daily_token_cap")
if [ "$_cap" = "500000" ]; then PASS=$((PASS+1)); else echo "FAIL: xgh_config_get returned '$_cap', expected '500000'"; FAIL=$((FAIL+1)); fi
export HOME="$_HOME_BAK"

# Config template must exist in repo
assert_file_exists "config/ingest-template.yaml"
# techpack references all ingest components
assert_contains "techpack.yaml" "retrieve-skill"
assert_contains "techpack.yaml" "analyze-skill"
assert_contains "techpack.yaml" "workspace-write"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
