#!/usr/bin/env bash
# test-trigger.sh — Validates trigger engine structure and conventions

PASS=0; FAIL=0
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"

assert_file_exists() {
  if [ -f "$1" ]; then
    echo "PASS: $2"; PASS=$((PASS+1))
  else
    echo "FAIL: $2 — missing: $1"; FAIL=$((FAIL+1))
  fi
}

assert_dir_exists() {
  if [ -d "$1" ]; then
    echo "PASS: $2"; PASS=$((PASS+1))
  else
    echo "FAIL: $2 — missing dir: $1"; FAIL=$((FAIL+1))
  fi
}

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then
    echo "PASS: $3"; PASS=$((PASS+1))
  else
    echo "FAIL: $3 — '$2' not found in $1"; FAIL=$((FAIL+1))
  fi
}

# ── Skill + command exist ─────────────────────────────────────────────────────
assert_file_exists "$PLUGIN_DIR/skills/trigger/trigger.md"   "trigger skill exists"
assert_file_exists "$PLUGIN_DIR/commands/trigger.md"         "trigger command exists"
assert_file_exists "$PLUGIN_DIR/hooks/post-tool-use.sh"      "post-tool-use hook exists"

# ── trigger.md content ───────────────────────────────────────────────────────
TRIGGER_SKILL="$PLUGIN_DIR/skills/trigger/trigger.md"
assert_contains "$TRIGGER_SKILL" "xgh:trigger"               "trigger skill has correct name"
assert_contains "$TRIGGER_SKILL" "list"                       "trigger skill covers list command"
assert_contains "$TRIGGER_SKILL" "silence"                    "trigger skill covers silence command"
assert_contains "$TRIGGER_SKILL" "test"                       "trigger skill covers test command"
assert_contains "$TRIGGER_SKILL" "history"                    "trigger skill covers history command"
assert_contains "$TRIGGER_SKILL" '~/.xgh/triggers/'          "trigger skill references triggers dir"
assert_contains "$TRIGGER_SKILL" '.state.json'               "trigger skill references state file"
assert_contains "$TRIGGER_SKILL" "action_level"              "trigger skill documents action_level"
assert_contains "$TRIGGER_SKILL" "backoff"                   "trigger skill documents backoff"
assert_contains "$TRIGGER_SKILL" "fired_items"               "trigger skill documents dedup"

# ── post-tool-use.sh content ─────────────────────────────────────────────────
HOOK="$PLUGIN_DIR/hooks/post-tool-use.sh"
assert_contains "$HOOK" "local_command"                      "hook uses local_command source_type"
assert_contains "$HOOK" "source: local"                      "hook checks for local triggers"
assert_contains "$HOOK" '~/.xgh/triggers'                   "hook reads trigger dir"
assert_contains "$HOOK" '~/.xgh/inbox'                      "hook writes to inbox"

# ── analyze.md integration ───────────────────────────────────────────────────
ANALYZE="$PLUGIN_DIR/skills/analyze/analyze.md"
assert_contains "$ANALYZE" "trigger"                         "analyze has trigger evaluation"
assert_contains "$ANALYZE" "standard"                        "analyze references standard path"
assert_contains "$ANALYZE" "triggers.yaml"                   "analyze reads global trigger config"

# ── retrieve.md integration ──────────────────────────────────────────────────
RETRIEVE="$PLUGIN_DIR/skills/retrieve/retrieve.md"
assert_contains "$RETRIEVE" "fast"                           "retrieve has fast-path trigger evaluation"
assert_contains "$RETRIEVE" "trigger"                        "retrieve references trigger engine"

# ── init.md integration ──────────────────────────────────────────────────────
INIT="$PLUGIN_DIR/skills/init/init.md"
assert_contains "$INIT" '~/.xgh/triggers'                   "init creates triggers directory"
assert_contains "$INIT" "triggers.yaml"                      "init creates global trigger config"

# ── doctor.md integration ────────────────────────────────────────────────────
DOCTOR="$PLUGIN_DIR/skills/doctor/doctor.md"
assert_contains "$DOCTOR" "trigger"                          "doctor has trigger health check"
assert_contains "$DOCTOR" "triggers.yaml"                    "doctor checks global trigger config"

# ── track.md integration ─────────────────────────────────────────────────────
TRACK="$PLUGIN_DIR/skills/track/track.md"
assert_contains "$TRACK" "trigger"                           "track suggests triggers after provider generation"

# ── schedule.md integration ──────────────────────────────────────────────────
SCHEDULE="$PLUGIN_DIR/skills/schedule/schedule.md"
assert_contains "$SCHEDULE" "trigger"                        "schedule evaluates schedule-type triggers"
assert_contains "$SCHEDULE" "source: schedule"              "schedule references schedule event source"

# ── example triggers ─────────────────────────────────────────────────────────
assert_dir_exists  "$PLUGIN_DIR/triggers/examples"           "triggers/examples/ directory exists"
assert_file_exists "$PLUGIN_DIR/triggers/examples/README.md" "triggers examples README exists"
assert_file_exists "$PLUGIN_DIR/triggers/examples/p0-alert.yaml"          "p0-alert example exists"
assert_file_exists "$PLUGIN_DIR/triggers/examples/pr-stale-reminder.yaml" "pr-stale example exists"
assert_file_exists "$PLUGIN_DIR/triggers/examples/npm-post-publish.yaml"  "npm-post-publish example exists"
assert_file_exists "$PLUGIN_DIR/triggers/examples/weekly-standup.yaml"    "weekly-standup example exists"

# ── example trigger content ──────────────────────────────────────────────────
P0="$PLUGIN_DIR/triggers/examples/p0-alert.yaml"
assert_contains "$P0" "schema_version"                       "p0-alert has schema_version"
assert_contains "$P0" "action_level"                         "p0-alert has action_level"
assert_contains "$P0" "backoff"                              "p0-alert has backoff policy"

NPM="$PLUGIN_DIR/triggers/examples/npm-post-publish.yaml"
assert_contains "$NPM" "source: local"                       "npm-post-publish uses local source"
assert_contains "$NPM" "npm publish"                         "npm-post-publish matches npm command"

STANDUP="$PLUGIN_DIR/triggers/examples/weekly-standup.yaml"
assert_contains "$STANDUP" "source: schedule"                "weekly-standup uses schedule source"
assert_contains "$STANDUP" "cron"                            "weekly-standup has cron expression"

# ── session-start.sh integration ─────────────────────────────────────────────
SESSION_START="$PLUGIN_DIR/hooks/session-start.sh"
assert_contains "$SESSION_START" 'triggers'                  "session-start creates triggers dir"

# ── prompt-based skill triggering tests ──────────────────────────────────────
assert_dir_exists  "$PLUGIN_DIR/tests/skill-triggering"                    "skill-triggering dir exists"
assert_file_exists "$PLUGIN_DIR/tests/skill-triggering/run-test.sh"        "run-test.sh exists"
assert_file_exists "$PLUGIN_DIR/tests/skill-triggering/run-all.sh"         "run-all.sh exists"
assert_file_exists "$PLUGIN_DIR/tests/skill-triggering/run-multiturn-test.sh" "run-multiturn-test.sh exists"

PROMPTS_DIR="$PLUGIN_DIR/tests/skill-triggering/prompts"
assert_dir_exists  "$PROMPTS_DIR"                  "prompts/ dir exists"
assert_file_exists "$PROMPTS_DIR/retrieve.txt"     "retrieve prompt exists"
assert_file_exists "$PROMPTS_DIR/analyze.txt"      "analyze prompt exists"
assert_file_exists "$PROMPTS_DIR/briefing.txt"     "briefing prompt exists"
assert_file_exists "$PROMPTS_DIR/implement.txt"    "implement prompt exists"
assert_file_exists "$PROMPTS_DIR/investigate.txt"  "investigate prompt exists"
assert_file_exists "$PROMPTS_DIR/track.txt"        "track prompt exists"
assert_file_exists "$PROMPTS_DIR/doctor.txt"       "doctor prompt exists"
assert_file_exists "$PROMPTS_DIR/index.txt"        "index prompt exists"

# Runner scripts must have key content
assert_contains "$PLUGIN_DIR/tests/skill-triggering/run-test.sh"     "dangerously-skip-permissions"  "run-test.sh uses dangerously-skip-permissions"
assert_contains "$PLUGIN_DIR/tests/skill-triggering/run-test.sh"     "output-format stream-json"      "run-test.sh uses stream-json"
assert_contains "$PLUGIN_DIR/tests/skill-triggering/run-test.sh"     '"name":"Skill"'                 'run-test.sh greps for Skill tool'
assert_contains "$PLUGIN_DIR/tests/skill-triggering/run-all.sh"      "run-test.sh"                    "run-all.sh calls run-test.sh"
assert_contains "$PLUGIN_DIR/tests/skill-triggering/run-multiturn-test.sh" "xgh:briefing"            "multiturn test targets xgh:briefing"

# ── Result ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
