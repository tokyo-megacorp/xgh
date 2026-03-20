#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_file_exists() {
  if [[ -f "$1" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: missing file $1"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  if ! grep -qi "$2" "$1" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 still contains '$2'"
    FAIL=$((FAIL + 1))
  fi
}

assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_output() {
  local output
  output=$(bash "$1")
  if python3 - "$output" <<'PY'
import json
import sys
json.loads(sys.argv[1])
PY
  then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 did not emit valid JSON"
    FAIL=$((FAIL + 1))
  fi
}

assert_output_contains() {
  local output
  output=$(bash "$1")
  if [[ "$output" == *"$2"* ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: expected output from $1 to contain '$2'"
    FAIL=$((FAIL + 1))
  fi
}

# ── Basic file existence ──────────────────────────────────
assert_file_exists "hooks/session-start.sh"
assert_file_exists "hooks/prompt-submit.sh"

assert_not_contains "hooks/session-start.sh" "placeholder"
assert_not_contains "hooks/prompt-submit.sh" "placeholder"
assert_not_contains "hooks/session-start.sh" "not yet implemented"

# ── session-start: structured JSON output ─────────────────
# Create a temp context tree with mock .md files
TMPDIR_CT=$(mktemp -d)
trap "rm -rf $TMPDIR_CT" EXIT

mkdir -p "$TMPDIR_CT/backend/auth"
mkdir -p "$TMPDIR_CT/frontend"
mkdir -p "$TMPDIR_CT/_archived"

cat > "$TMPDIR_CT/backend/auth/jwt-patterns.md" << 'MDEOF'
---
title: JWT Patterns
importance: 92
maturity: core
---
Use short-lived access tokens.
Rotate refresh tokens on each use.
Store tokens in httpOnly cookies.
MDEOF

cat > "$TMPDIR_CT/frontend/state-management.md" << 'MDEOF'
---
title: State Management
importance: 80
maturity: validated
---
Prefer server state over client state.
Use React Query for server data.
Keep local state minimal.
MDEOF

cat > "$TMPDIR_CT/_archived/old-stuff.md" << 'MDEOF'
---
title: Old Stuff
importance: 99
maturity: core
---
Should be excluded from results.
MDEOF

cat > "$TMPDIR_CT/_index.md" << 'MDEOF'
---
title: Index
importance: 100
maturity: core
---
Should be excluded.
MDEOF

# Run session-start with the temp context tree
SS_OUTPUT=$(XGH_CONTEXT_TREE="$TMPDIR_CT" XGH_BRIEFING="off" bash hooks/session-start.sh)

# Validate JSON and keys
SS_VALID=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    keys = set(d.keys())
    required = {'result', 'contextFiles', 'briefingTrigger'}
    if required.issubset(keys):
        print('yes')
    else:
        print('no:missing:' + str(required - keys))
except Exception as e:
    print('no:' + str(e))
" "$SS_OUTPUT")
assert_eq "session-start has required keys" "$SS_VALID" "yes"

# Validate contextFiles is array of objects with correct keys
SS_CF_VALID=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
files = d.get('contextFiles', [])
if not isinstance(files, list) or len(files) == 0:
    print('no:empty-or-not-list')
    sys.exit(0)
required_keys = {'path', 'title', 'importance', 'maturity', 'excerpt'}
for f in files:
    if not required_keys.issubset(set(f.keys())):
        print('no:missing-keys:' + str(required_keys - set(f.keys())))
        sys.exit(0)
print('yes')
" "$SS_OUTPUT")
assert_eq "contextFiles has correct structure" "$SS_CF_VALID" "yes"

# Validate briefingTrigger is always full (no env var gate)
SS_BT=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d.get('briefingTrigger', ''))
" "$SS_OUTPUT")
assert_eq "briefingTrigger is always full" "$SS_BT" "full"

# Validate _archived and _index.md are excluded
SS_NO_ARCHIVED=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
paths = [f['path'] for f in d.get('contextFiles', [])]
has_bad = any('_archived' in p or '_index.md' in p for p in paths)
print('yes' if not has_bad else 'no')
" "$SS_OUTPUT")
assert_eq "excluded _archived and _index.md" "$SS_NO_ARCHIVED" "yes"

# Validate schedulerTrigger=on by default (no env var gate)
SS_SCHED_DEFAULT=$(XGH_CONTEXT_TREE="$TMPDIR_CT" bash hooks/session-start.sh)
SS_ST_DEFAULT=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d.get('schedulerTrigger', ''))
" "$SS_SCHED_DEFAULT")
assert_eq "schedulerTrigger default=on" "$SS_ST_DEFAULT" "on"

# Validate schedulerInstructions present by default (with a fake bash provider)
FAKE_PROVIDER="$HOME/.xgh/providers/_test_hook/fetch.sh"
mkdir -p "$(dirname "$FAKE_PROVIDER")"
echo "#!/usr/bin/env bash" > "$FAKE_PROVIDER"
SS_SI_OUT=$(XGH_CONTEXT_TREE="$TMPDIR_CT" bash hooks/session-start.sh)
rm -rf "$HOME/.xgh/providers/_test_hook"
SS_SI=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
v = d.get('schedulerInstructions', '')
print('yes' if v and 'retrieve-all.sh' in v and '/xgh-analyze' in v else 'no:' + repr(v))
" "$SS_SI_OUT")
assert_eq "schedulerInstructions contains cron prompts" "$SS_SI" "yes"

# Validate schedulerTrigger=paused when pause file exists
PAUSE_FILE="$HOME/.xgh/scheduler-paused"
mkdir -p "$HOME/.xgh"
touch "$PAUSE_FILE"
SS_SCHED_PAUSED=$(XGH_CONTEXT_TREE="$TMPDIR_CT" bash hooks/session-start.sh)
rm -f "$PAUSE_FILE"
SS_ST_PAUSED=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d.get('schedulerTrigger', ''))
" "$SS_SCHED_PAUSED")
assert_eq "schedulerTrigger paused when pause file exists" "$SS_ST_PAUSED" "paused"

# Validate schedulerInstructions absent (null) when paused
SS_SI_PAUSED=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print('null' if d.get('schedulerInstructions') is None else 'present')
" "$SS_SCHED_PAUSED")
assert_eq "schedulerInstructions null when paused" "$SS_SI_PAUSED" "null"

# ── prompt-submit: structured JSON output ─────────────────
PS_OUTPUT=$(PROMPT="implement a new login feature" bash hooks/prompt-submit.sh)

# prompt-submit emits valid JSON (may be empty {} when no nudge needed)
PS_VALID=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    print('yes' if isinstance(d, dict) else 'no')
except Exception as e:
    print('no:' + str(e))
" "$PS_OUTPUT")
assert_eq "prompt-submit emits valid JSON" "$PS_VALID" "yes"

# Static memory instructions live in xgh-instructions.md (not in hook output)
PS_STATIC=$(grep -q 'lcm_search' templates/xgh-instructions.md 2>/dev/null && echo "yes" || echo "no")
assert_eq "memory instructions in static xgh-instructions.md" "$PS_STATIC" "yes"

# General prompt also emits valid JSON
PS_GENERAL=$(PROMPT="what time is it?" bash hooks/prompt-submit.sh)
PS_VALID_G=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print('yes' if isinstance(d, dict) else 'no')
" "$PS_GENERAL")
assert_eq "prompt-submit general emits valid JSON" "$PS_VALID_G" "yes"

# Both hooks exit 0
bash hooks/session-start.sh > /dev/null 2>&1 && PASS=$((PASS + 1)) || { echo "FAIL: session-start.sh non-zero exit"; FAIL=$((FAIL + 1)); }
bash hooks/prompt-submit.sh > /dev/null 2>&1 && PASS=$((PASS + 1)) || { echo "FAIL: prompt-submit.sh non-zero exit"; FAIL=$((FAIL + 1)); }

# ── Context-mode enforcement ──────────────────────────────
# Context-mode plugin owns its own enforcement via PreToolUse hooks.
# xgh no longer duplicates this — no pre-read, post-edit, or post-ctx-call hooks.

# Test: schedulerInstructions mentions retrieve-all.sh (with a fake bash provider)
FAKE_PROVIDER2="$HOME/.xgh/providers/_test_hook2/fetch.sh"
mkdir -p "$(dirname "$FAKE_PROVIDER2")"
echo "#!/usr/bin/env bash" > "$FAKE_PROVIDER2"
SS_RETRIEVE=$(XGH_CONTEXT_TREE="$TMPDIR_CT" bash hooks/session-start.sh)
rm -rf "$HOME/.xgh/providers/_test_hook2"
SS_RETRIEVE_OK=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
si = d.get('schedulerInstructions', '')
print('yes' if 'retrieve-all.sh' in (si or '') else 'no')
" "$SS_RETRIEVE")
assert_eq "schedulerInstructions mentions retrieve-all.sh" "$SS_RETRIEVE_OK" "yes"

echo ""
echo "Hooks test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
