# Prompt-Based Skill Triggering Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add obra/superpowers-style prompt tests to xgh — run `claude -p` with natural-language and command prompts and verify the correct skill fires, giving us runtime tests for skill trigger descriptions rather than just file-structure linting.

**Architecture:** A standalone `tests/skill-triggering/` directory with a bash runner that invokes `claude -p "$PROMPT" --plugin-dir "$PLUGIN_DIR" --output-format stream-json`, then greps the JSON output for `"name":"Skill"` + `"skill":"xgh:<skillname>"` to verify invocation. 8 prompt files cover the key xgh skills. A `run-all.sh` orchestrates them. A separate `run-multiturn-test.sh` tests that skill triggering survives extended conversation context. Structural file-existence assertions are added to `tests/test-trigger.sh`.

**Tech Stack:** Bash, `claude -p` (non-interactive), `--output-format stream-json`, `--verbose`, `--plugin-dir`, `--dangerously-skip-permissions`

---

## File Map

| File | Action | Responsibility |
|------|---------|---------------|
| `tests/skill-triggering/run-test.sh` | Create | Single-skill test runner — invokes claude, greps result |
| `tests/skill-triggering/run-all.sh` | Create | Runs all 8 skill tests, prints summary |
| `tests/skill-triggering/run-multiturn-test.sh` | Create | Multi-turn continuity test for `xgh:briefing` |
| `tests/skill-triggering/prompts/retrieve.txt` | Create | Prompt for `xgh:retrieve` |
| `tests/skill-triggering/prompts/analyze.txt` | Create | Prompt for `xgh:analyze` |
| `tests/skill-triggering/prompts/briefing.txt` | Create | Prompt for `xgh:briefing` |
| `tests/skill-triggering/prompts/implement.txt` | Create | Prompt for `xgh:implement` |
| `tests/skill-triggering/prompts/investigate.txt` | Create | Prompt for `xgh:investigate` |
| `tests/skill-triggering/prompts/track.txt` | Create | Prompt for `xgh:track` |
| `tests/skill-triggering/prompts/doctor.txt` | Create | Prompt for `xgh:doctor` |
| `tests/skill-triggering/prompts/index.txt` | Create | Prompt for `xgh:index` |
| `tests/test-trigger.sh` | Modify | Add structural assertions for the new test files |

---

## Task 1: TDD anchor — structural assertions

Add file-existence checks to `tests/test-trigger.sh` for the new test infrastructure. These assertions will FAIL until Tasks 2–4 create the files — that's the TDD red state.

**Files:**
- Modify: `tests/test-trigger.sh`

- [ ] **Step 1: Open test-trigger.sh and read the existing structure**

Read the last 20 lines of `tests/test-trigger.sh` to understand where to append.

- [ ] **Step 2: Append structural assertions**

Add the following block at the end of `tests/test-trigger.sh`, before the `# ── Result ───` section:

```bash
# ── prompt-based skill triggering tests ──────────────────────────────────────
assert_dir_exists  "$PLUGIN_DIR/tests/skill-triggering"                    "skill-triggering dir exists"
assert_file_exists "$PLUGIN_DIR/tests/skill-triggering/run-test.sh"        "run-test.sh exists"
assert_file_exists "$PLUGIN_DIR/tests/skill-triggering/run-all.sh"         "run-all.sh exists"
assert_file_exists "$PLUGIN_DIR/tests/skill-triggering/run-multiturn-test.sh" "run-multiturn-test.sh exists"

PROMPTS_DIR="$PLUGIN_DIR/tests/skill-triggering/prompts"
assert_file_exists "$PROMPTS_DIR/retrieve.txt"     "retrieve prompt exists"
assert_file_exists "$PROMPTS_DIR/analyze.txt"      "analyze prompt exists"
assert_file_exists "$PROMPTS_DIR/briefing.txt"     "briefing prompt exists"
assert_file_exists "$PROMPTS_DIR/implement.txt"    "implement prompt exists"
assert_file_exists "$PROMPTS_DIR/investigate.txt"  "investigate prompt exists"
assert_file_exists "$PROMPTS_DIR/track.txt"        "track prompt exists"
assert_file_exists "$PROMPTS_DIR/doctor.txt"       "doctor prompt exists"
assert_file_exists "$PROMPTS_DIR/index.txt"        "index prompt exists"

# Runner scripts must be executable
assert_contains "$PLUGIN_DIR/tests/skill-triggering/run-test.sh"     "dangerously-skip-permissions"  "run-test.sh uses dangerously-skip-permissions"
assert_contains "$PLUGIN_DIR/tests/skill-triggering/run-test.sh"     "output-format stream-json"      "run-test.sh uses stream-json"
assert_contains "$PLUGIN_DIR/tests/skill-triggering/run-test.sh"     '"name":"Skill"'                 'run-test.sh greps for Skill tool'
assert_contains "$PLUGIN_DIR/tests/skill-triggering/run-all.sh"      "run-test.sh"                    "run-all.sh calls run-test.sh"
assert_contains "$PLUGIN_DIR/tests/skill-triggering/run-multiturn-test.sh" "xgh:briefing"            "multiturn test targets xgh:briefing"
```

- [ ] **Step 3: Run the structural tests to confirm they fail (red)**

```bash
bash tests/test-trigger.sh 2>&1 | tail -5
```

Expected: multiple FAIL lines for missing skill-triggering files. That's correct — TDD red state.

- [ ] **Step 4: Commit the failing tests**

```bash
git add tests/test-trigger.sh
git commit -m "test: add structural assertions for prompt skill-triggering tests (red)"
```

---

## Task 2: Core runner script (run-test.sh)

**Files:**
- Create: `tests/skill-triggering/run-test.sh`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p tests/skill-triggering/prompts
```

- [ ] **Step 2: Write run-test.sh**

Create `tests/skill-triggering/run-test.sh`:

```bash
#!/usr/bin/env bash
# Test skill triggering — verifies that a prompt causes Claude to invoke the named skill
# Usage: ./run-test.sh <skill-name> <prompt-file>
#
# Tests whether Claude triggers a skill based on a prompt.
# Supports both natural-language prompts and explicit /command prompts.
#
# Examples:
#   ./run-test.sh xgh:briefing prompts/briefing.txt
#   ./run-test.sh xgh:track   prompts/track.txt

set -euo pipefail

SKILL_NAME="$1"
PROMPT_FILE="$2"

if [ -z "$SKILL_NAME" ] || [ -z "$PROMPT_FILE" ]; then
    echo "Usage: $0 <skill-name> <prompt-file>"
    echo "Example: $0 xgh:briefing prompts/briefing.txt"
    exit 1
fi

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

TIMESTAMP=$(date +%s)
OUTPUT_DIR="/tmp/xgh-skill-tests/${TIMESTAMP}/${SKILL_NAME//:/--}"
mkdir -p "$OUTPUT_DIR"

PROMPT=$(cat "$PROMPT_FILE")

echo "=== xgh Skill Triggering Test ==="
echo "Skill:       $SKILL_NAME"
echo "Prompt file: $PROMPT_FILE"
echo "Plugin dir:  $PLUGIN_DIR"
echo ""

cp "$PROMPT_FILE" "$OUTPUT_DIR/prompt.txt"

LOG_FILE="$OUTPUT_DIR/claude-output.json"
cd "$OUTPUT_DIR"

echo "Running claude -p ..."
# --verbose is required for --output-format stream-json with -p
timeout 120 claude -p "$PROMPT" \
    --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    --verbose \
    --output-format stream-json \
    > "$LOG_FILE" 2>&1 || true

echo ""
echo "=== Results ==="

# Extract just the skill base name (xgh:briefing → briefing) for flexible matching
# Matches both "xgh:briefing" and bare "briefing" in case of namespace variations
SKILL_BASE="${SKILL_NAME##*:}"
SKILL_PATTERN='"skill":"([^"]*:)?'"${SKILL_BASE}"'"'

if grep -q '"name":"Skill"' "$LOG_FILE" && grep -qE "$SKILL_PATTERN" "$LOG_FILE"; then
    echo "✅ PASS: Skill '$SKILL_NAME' was triggered"
    TRIGGERED=true
else
    echo "❌ FAIL: Skill '$SKILL_NAME' was NOT triggered"
    TRIGGERED=false
fi

# Show all skills that were triggered
echo ""
echo "Skills triggered:"
grep -o '"skill":"[^"]*"' "$LOG_FILE" 2>/dev/null | sort -u || echo "  (none)"

# Show first assistant response (truncated)
echo ""
echo "First assistant response (truncated to 300 chars):"
grep '"type":"assistant"' "$LOG_FILE" 2>/dev/null | head -1 \
    | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); content=d.get('message',{}).get('content',[]); print(content[0].get('text','')[:300] if content else '')" \
    2>/dev/null || echo "  (could not extract)"

echo ""
echo "Full log: $LOG_FILE"

if [ "$TRIGGERED" = "true" ]; then
    exit 0
else
    exit 1
fi
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x tests/skill-triggering/run-test.sh
```

- [ ] **Step 4: Verify bash syntax**

```bash
bash -n tests/skill-triggering/run-test.sh && echo "Syntax OK"
```

Expected: `Syntax OK`

---

## Task 3: Prompt files (8 skills)

Write one prompt file per skill. Prompts are the exact text sent to Claude — no meta-commentary, no skill names where avoidable.

**Files:**
- Create: all 8 files in `tests/skill-triggering/prompts/`

**Context on prompt design:**
- `xgh:retrieve`, `xgh:analyze`, `xgh:investigate`, `xgh:implement`: command-triggered skills — use the explicit slash command. This tests the command→skill dispatch path.
- `xgh:briefing`, `xgh:track`, `xgh:doctor`, `xgh:index`: have natural-language triggers — use real-user phrasing.

- [ ] **Step 1: Write retrieve.txt**

```
/xgh-retrieve
```

File: `tests/skill-triggering/prompts/retrieve.txt`

- [ ] **Step 2: Write analyze.txt**

```
/xgh-analyze
```

File: `tests/skill-triggering/prompts/analyze.txt`

- [ ] **Step 3: Write briefing.txt**

```
What needs my attention right now? I'm starting my work session.
```

File: `tests/skill-triggering/prompts/briefing.txt`

- [ ] **Step 4: Write implement.txt**

```
/xgh-implement https://jira.example.com/browse/PROJ-42
```

File: `tests/skill-triggering/prompts/implement.txt`

- [ ] **Step 5: Write investigate.txt**

```
/xgh-investigate
```

File: `tests/skill-triggering/prompts/investigate.txt`

- [ ] **Step 6: Write track.txt**

```
Add my new iOS project to xgh monitoring. The Slack channel is #mobile-app and the Jira board is MOBILE.
```

File: `tests/skill-triggering/prompts/track.txt`

- [ ] **Step 7: Write doctor.txt**

```
Is my xgh pipeline healthy? Check if everything is connected and running.
```

File: `tests/skill-triggering/prompts/doctor.txt`

- [ ] **Step 8: Write index.txt**

```
Index this codebase into memory so you understand how it works.
```

File: `tests/skill-triggering/prompts/index.txt`

- [ ] **Step 9: Commit prompt files and runner**

```bash
git add tests/skill-triggering/
git commit -m "feat(tests): add skill-triggering runner and 8 prompt files"
```

---

## Task 4: run-all.sh orchestrator

**Files:**
- Create: `tests/skill-triggering/run-all.sh`

- [ ] **Step 1: Write run-all.sh**

Create `tests/skill-triggering/run-all.sh`:

```bash
#!/usr/bin/env bash
# Run all xgh skill triggering tests
# Usage: ./run-all.sh
#
# NOTE: This is an opt-in test suite — it invokes claude -p and costs API tokens.
# Do NOT call from tests/test-config.sh.
# Run manually when editing skill trigger descriptions.
#
# Cost estimate: ~8 prompts × 1 turn ≈ ~$0.40 per full suite run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="$SCRIPT_DIR/prompts"

# skill-name → prompt-file mapping
# Format: "skill_base_name:prompt_file"
TESTS=(
    "xgh:retrieve:retrieve.txt"
    "xgh:analyze:analyze.txt"
    "xgh:briefing:briefing.txt"
    "xgh:implement:implement.txt"
    "xgh:investigate:investigate.txt"
    "xgh:track:track.txt"
    "xgh:doctor:doctor.txt"
    "xgh:index:index.txt"
)

echo "=== xgh Skill Triggering Test Suite ==="
echo "Plugin dir: $(cd "$SCRIPT_DIR/../.." && pwd)"
echo ""

PASSED=0
FAILED=0
RESULTS=()

for entry in "${TESTS[@]}"; do
    # Parse "namespace:skill:file" — split on last colon for the file
    SKILL="${entry%:*}"          # everything before last colon = skill name (e.g. xgh:briefing)
    PROMPT_FILE="${entry##*:}"   # everything after last colon = filename

    FULL_PROMPT="$PROMPTS_DIR/$PROMPT_FILE"

    if [ ! -f "$FULL_PROMPT" ]; then
        echo "⚠️  SKIP: No prompt file for $SKILL ($FULL_PROMPT)"
        continue
    fi

    echo "--- Testing: $SKILL ---"

    if "$SCRIPT_DIR/run-test.sh" "$SKILL" "$FULL_PROMPT"; then
        PASSED=$((PASSED + 1))
        RESULTS+=("✅ $SKILL")
    else
        FAILED=$((FAILED + 1))
        RESULTS+=("❌ $SKILL")
    fi

    echo ""
done

echo "=== Summary ==="
for result in "${RESULTS[@]}"; do
    echo "  $result"
done
echo ""
echo "Passed: $PASSED / $((PASSED + FAILED))"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x tests/skill-triggering/run-all.sh
```

- [ ] **Step 3: Verify bash syntax**

```bash
bash -n tests/skill-triggering/run-all.sh && echo "Syntax OK"
```

Expected: `Syntax OK`

---

## Task 5: Multi-turn continuity test

Tests that skill triggering survives an extended conversation — catches the failure mode where Claude stops invoking skills after many turns.

**Files:**
- Create: `tests/skill-triggering/run-multiturn-test.sh`

- [ ] **Step 1: Write run-multiturn-test.sh**

Create `tests/skill-triggering/run-multiturn-test.sh`:

```bash
#!/usr/bin/env bash
# Multi-turn continuity test — verifies skill triggering after conversation context accumulation
#
# This reproduces the failure mode where Claude skips skill invocation after
# extended conversation. Tests xgh:briefing since it has natural-language triggers.
#
# Usage: ./run-multiturn-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

TIMESTAMP=$(date +%s)
OUTPUT_DIR="/tmp/xgh-skill-tests/${TIMESTAMP}/multiturn"
mkdir -p "$OUTPUT_DIR"

PROJECT_DIR="$OUTPUT_DIR/project"
mkdir -p "$PROJECT_DIR"

echo "=== xgh Multi-Turn Skill Continuity Test ==="
echo "Skill under test: xgh:briefing"
echo "Output dir: $OUTPUT_DIR"
echo ""

cd "$PROJECT_DIR"

# Turn 1: Start a routine conversation
echo ">>> Turn 1: Starting a routine work conversation..."
TURN1_LOG="$OUTPUT_DIR/turn1.json"
claude -p "I just got in. Let me check some things. What's the status of the codebase?" \
    --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    --verbose \
    --output-format stream-json \
    > "$TURN1_LOG" 2>&1 || true
echo "Turn 1 complete."

# Turn 2: Continue with more context
echo ""
echo ">>> Turn 2: Accumulating more conversation context..."
TURN2_LOG="$OUTPUT_DIR/turn2.json"
claude -p "Thanks. I also noticed some Slack messages piling up from last night. We had an incident." \
    --continue \
    --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    --verbose \
    --output-format stream-json \
    > "$TURN2_LOG" 2>&1 || true
echo "Turn 2 complete."

# Turn 3: THE TEST — natural language trigger after context accumulation
echo ""
echo ">>> Turn 3: Triggering xgh:briefing after context accumulation..."
TURN3_LOG="$OUTPUT_DIR/turn3.json"
claude -p "Ok, enough context. What needs my attention right now? Give me a full briefing." \
    --continue \
    --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    --verbose \
    --output-format stream-json \
    > "$TURN3_LOG" 2>&1 || true
echo "Turn 3 complete."

echo ""
echo "=== Results ==="

SKILL_PATTERN='"skill":"([^"]*:)?briefing"'
if grep -q '"name":"Skill"' "$TURN3_LOG" && grep -qE "$SKILL_PATTERN" "$TURN3_LOG"; then
    echo "✅ PASS: xgh:briefing triggered in Turn 3 (after context accumulation)"
    TRIGGERED=true
else
    echo "❌ FAIL: xgh:briefing NOT triggered in Turn 3"
    echo "  Skills triggered in Turn 3:"
    grep -o '"skill":"[^"]*"' "$TURN3_LOG" 2>/dev/null | sort -u || echo "  (none)"
    TRIGGERED=false
fi

echo ""
echo "Logs: $OUTPUT_DIR"

if [ "$TRIGGERED" = "true" ]; then
    exit 0
else
    exit 1
fi
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x tests/skill-triggering/run-multiturn-test.sh
```

- [ ] **Step 3: Verify bash syntax**

```bash
bash -n tests/skill-triggering/run-multiturn-test.sh && echo "Syntax OK"
```

Expected: `Syntax OK`

- [ ] **Step 4: Commit run-all.sh and run-multiturn-test.sh**

```bash
git add tests/skill-triggering/run-all.sh tests/skill-triggering/run-multiturn-test.sh
git commit -m "feat(tests): add run-all.sh and multi-turn continuity test"
```

---

## Task 6: Structural tests go green

Run the structural assertions added in Task 1 — they should all pass now.

**Files:** (no changes)

- [ ] **Step 1: Run structural tests**

```bash
bash tests/test-trigger.sh 2>&1 | tail -10
```

Expected: all new assertions PASS. The total pass count should increase by ~13.

- [ ] **Step 2: Run the full test suite**

```bash
bash tests/test-config.sh
```

Expected: all tests pass (structural tests only — no API calls in the normal suite).

- [ ] **Step 3: No commit needed here** — Task 1 already committed `test-trigger.sh` and Tasks 2–5 committed the test files. All changes are in git. Verify with `git status` — should be clean.

---

## Task 7: Live validation — smoke test one skill

Run a single live test to verify the runner actually works end-to-end. Use `xgh:track` since it has the most natural natural-language trigger (least likely to be a false-failure from prompt ambiguity).

**Files:** (no changes, possibly prompt tweaks)

- [ ] **Step 1: Run a single live test**

```bash
cd tests/skill-triggering
./run-test.sh xgh:track prompts/track.txt
```

Expected:
- Output shows `✅ PASS: Skill 'xgh:track' was triggered`
- `Skills triggered:` shows `"skill":"xgh:track"` (possibly with namespace)

- [ ] **Step 2: If FAIL — inspect the log**

```bash
# The log path is printed in the output, e.g.:
cat /tmp/xgh-skill-tests/<timestamp>/xgh--track/claude-output.json | \
  python3 -c "import sys,json; [print(json.dumps(json.loads(l), indent=2)) for l in sys.stdin if '\"name\":\"Skill\"' in l or '\"type\":\"assistant\"' in l]" 2>/dev/null | head -100
```

If the skill fired but with a different name (e.g. `"skill":"xgh-track"` vs `"skill":"xgh:track"`), update `SKILL_PATTERN` in `run-test.sh` to match the actual format.

If no skill fired at all, update the prompt to be more explicitly aligned with the skill's trigger description. Read: `skills/track/track.md` (first 20 lines) to see exact trigger wording, then revise `prompts/track.txt`.

- [ ] **Step 3: Commit any prompt fixes**

```bash
git add tests/skill-triggering/prompts/
git commit -m "fix(tests): tune prompts based on live validation"
```

---

## Notes for the implementer

1. **Stream-json format**: `"name":"Skill"` appears in tool_use blocks. The skill name is in the `"input"` object as `"skill":"xgh:briefing"`. obra's pattern `'"skill":"([^"]*:)?skillname"'` matches both namespaced and bare names — use it.

2. **`--verbose` is required for stream-json**: Running `claude -p ... --output-format stream-json` without `--verbose` fails with: `Error: When using --print, --output-format=stream-json requires --verbose`. All invocations include `--verbose`.

3. **`--plugin-dir`**: Points to the local repo root. This loads the development version of the plugin. If xgh is also installed globally, both will be loaded — that's fine, since the skill names are unique.

4. **`--dangerously-skip-permissions`**: Required for non-interactive mode. These tests run in `/tmp/xgh-skill-tests/` which is safe.

5. **Skill name format**: xgh uses `xgh:briefing` (colon namespace). The grep uses `([^"]*:)?` prefix to handle both `xgh:briefing` and potential bare `briefing` matches.

6. **This suite is NOT called from `test-config.sh`**: It costs API tokens. Run manually: `cd tests/skill-triggering && ./run-all.sh`

7. **Prompt design**: 4 command-only skills (`retrieve`, `analyze`, `investigate`, `implement`) use slash command prompts — testing the command→skill dispatch path. 4 skills with natural-language triggers (`briefing`, `track`, `doctor`, `index`) use real-user phrasing — testing the NL→skill path.
