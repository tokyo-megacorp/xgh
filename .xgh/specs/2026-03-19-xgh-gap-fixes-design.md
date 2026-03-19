# Design: xgh Gap Fixes (1, 3, 4, 5, 7)

**Date:** 2026-03-19
**Status:** Approved
**Scope:** xgh-side fixes only. Gaps 2 and 6 are lossless-claude upstream (see sibling RFCs).

---

## Gap 1 — Scheduler never starts (Critical)

**Root cause:** `session-start.sh` gates cron registration on `XGH_SCHEDULER` env var (defaults to `off`). Neither installer nor `/xgh-init` sets it. The entire automated pipeline is dead on arrival.

**Fix:** Remove the env var gate entirely. Session-start always registers the default cron jobs. Opt-out via `/xgh-schedule pause`.

### Changes

**`plugin/hooks/session-start.sh`:**
- Remove `XGH_SCHEDULER` env var check (lines ~54-67)
- Remove `XGH_BRIEFING` env var check (lines ~47-52)
- Always emit `schedulerTrigger: "on"` and `briefingTrigger: "full"` in JSON output
- Register default cron jobs unconditionally:
  - retrieve: `*/5 * * * *`
  - analyze: `*/30 * * * *`
  - deep-retrieve: `0 * * * *`

**`plugin/skills/init/init.md`:**
- Remove Step 7b (writing `export XGH_SCHEDULER=on` to shell profile)
- Remove any references to `XGH_SCHEDULER` or `XGH_BRIEFING` env vars
- Add a note: "Scheduler is active by default. Use `/xgh-schedule pause` to disable."

**`plugin/skills/schedule/schedule.md`:**
- Remove references to `XGH_SCHEDULER` env var
- `pause` subcommand remains (stores pause state in `~/.xgh/scheduler-paused`)
- Session-start checks for pause file before registering crons

**`config/ingest-template.yaml`:**
- Remove `XGH_SCHEDULER` and `XGH_BRIEFING` documentation
- Add `schedule.paused: false` field (written by `/xgh-schedule pause/resume`)

### Pause mechanism

```
/xgh-schedule pause  → touch ~/.xgh/scheduler-paused
/xgh-schedule resume → rm ~/.xgh/scheduler-paused

session-start.sh:
  if [ -f ~/.xgh/scheduler-paused ]; then
    # skip cron registration, emit schedulerTrigger: "paused"
  else
    # register crons normally
  fi
```

Simple file-based flag. No env vars, no shell profile editing, no hidden configuration.

---

## Gap 3 — Dual memory hooks (High)

**Root cause:** Two `UserPromptSubmit` hooks fire simultaneously — `xgh-prompt-submit.sh` (says use `lcm_*`) and `continuous-learning-activator.sh` (says use `cipher_*`). Agent gets conflicting guidance every prompt.

**Fix:** Ensure only `prompt-submit.sh` exists with `lcm_*` guidance. Remove any `continuous-learning-activator.sh` references.

### Changes

**`install.sh`:**
- Add cleanup step: remove `continuous-learning-activator.sh` from `.claude/hooks/` if it exists (handles upgrades from older installs)
- Verify no cipher-related hooks are registered in `settings.local.json`

**`plugin/hooks/prompt-submit.sh`:**
- Audit for any remaining `cipher_*` references (migration plan should have caught these, but verify)

**`plugin/skills/init/init.md`:**
- Step 0b (stale file cleanup) already removes old skill copies — extend to remove `continuous-learning-activator.sh` from hooks

### Verification

```bash
# After install, no cipher hooks should exist:
grep -r "cipher_" .claude/hooks/ && echo "FAIL: cipher references in hooks" || echo "PASS"
grep -r "continuous-learning" .claude/ && echo "FAIL: stale activator" || echo "PASS"
```

---

## Gap 4 — Cursors not updated after retrieve (Medium)

**Root cause:** `retrieve.md` Step 9 instructs the agent to update `.cursors.json`, but it's a prose instruction. The agent may skip it, partially execute it, or construct invalid JSON.

**Fix:** Add a deterministic bash script for atomic cursor updates. The retrieve skill calls the script instead of relying on agent-constructed jq.

### New file: `plugin/scripts/update-cursor.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: update-cursor.sh <channel-id> <timestamp>
# Atomically updates the cursor for a channel in ~/.xgh/inbox/.cursors.json

CURSORS_FILE="${HOME}/.xgh/inbox/.cursors.json"
CHANNEL="$1"
TIMESTAMP="$2"

# Ensure file exists
[ -f "$CURSORS_FILE" ] || echo '{}' > "$CURSORS_FILE"

# Atomic update: write to temp, then move
TMP="$(mktemp)"
jq --arg ch "$CHANNEL" --arg ts "$TIMESTAMP" '.[$ch] = $ts' "$CURSORS_FILE" > "$TMP"
mv "$TMP" "$CURSORS_FILE"
```

### Changes

**`plugin/skills/retrieve/retrieve.md`:**
- Step 9: Replace prose-based cursor update with:
  ```
  For each channel processed, run:
  bash plugin/scripts/update-cursor.sh "<channel-id>" "<latest-timestamp>"
  ```
- Step 1: Replace prose-based cursor read with:
  ```
  Read cursors: cat ~/.xgh/inbox/.cursors.json
  For each channel, only fetch messages after the cursor timestamp.
  ```

---

## Gap 5 — Retention never enforced (Low)

**Root cause:** `analyze.md` Step 9 says "purge >7 days old" but it's prose — the agent inconsistently executes it. 38 files accumulated over 15 days in `~/.xgh/inbox/processed/`.

**Fix:** Move retention to `session-start.sh` as deterministic bash. Runs every session, no agent involvement.

### Changes

**`plugin/hooks/session-start.sh`:**

Add after context tree loading, before JSON output:

```bash
# ── Retention cleanup ──
_xgh_home="${HOME}/.xgh"
if [ -d "${_xgh_home}/inbox/processed" ]; then
  find "${_xgh_home}/inbox/processed/" -type f -mtime +7 -delete 2>/dev/null || true
fi
if [ -d "${_xgh_home}/digests" ]; then
  find "${_xgh_home}/digests/" -type f -mtime +30 -delete 2>/dev/null || true
fi
if [ -d "${_xgh_home}/logs" ]; then
  find "${_xgh_home}/logs/" -type f -mtime +7 -delete 2>/dev/null || true
fi
```

**`plugin/skills/analyze/analyze.md`:**
- Step 9: Remove the prose about purging processed files (now handled by session-start hook)
- Keep the "move to processed/" instruction (that part works fine)

### Retention periods (from ingest-template.yaml)

| Path | Retention | Source |
|---|---|---|
| `~/.xgh/inbox/processed/` | 7 days | `retention.inbox_processed` |
| `~/.xgh/digests/` | 30 days | `retention.digests` |
| `~/.xgh/logs/` | 7 days | `retention.log_retention` |

---

## Gap 7 — Custom skills have no trigger (Medium)

**Root cause:** Only retrieve/analyze/deep-retrieve are registered as cron jobs in session-start. Other skills (briefing, command-center pulse) say "run periodically" in their docs but have no CronCreate registration.

**Fix:** Extend the default cron set in session-start and add a configurable `schedule.jobs` section to ingest.yaml.

### Changes

**`plugin/hooks/session-start.sh`:**

Default cron set becomes:

```
retrieve:       */5 * * * *
analyze:        */30 * * * *
deep-retrieve:  0 * * * *
```

Plus user-defined jobs from `~/.xgh/ingest.yaml` → `schedule.jobs[]`:

```bash
# Read custom jobs from ingest.yaml (if yq is available)
if command -v yq &>/dev/null && [ -f "${_xgh_home}/ingest.yaml" ]; then
  _custom_jobs=$(yq -o=json '.schedule.jobs // []' "${_xgh_home}/ingest.yaml" 2>/dev/null)
  # Emit as schedulerCustomJobs in JSON output for the agent to register via CronCreate
fi
```

**`config/ingest-template.yaml`:**

Add `schedule` section:

```yaml
schedule:
  paused: false
  jobs:
    # Default jobs (registered by session-start hook):
    # - retrieve:      */5 * * * *
    # - analyze:       */30 * * * *
    # - deep-retrieve: 0 * * * *
    #
    # Add custom periodic jobs below:
    # - skill: "/xgh-brief"
    #   cron: "0 8 * * 1-5"
    #   description: "Weekday morning briefing"
```

**`plugin/skills/schedule/schedule.md`:**

Add `add` subcommand:

```
/xgh-schedule add "/xgh-brief" "0 8 * * 1-5"
  → Appends to schedule.jobs in ~/.xgh/ingest.yaml
  → Registers CronCreate immediately
  → Persists across sessions (session-start reads it)
```

---

## Files Summary

| File | Action | Gaps |
|---|---|---|
| `plugin/hooks/session-start.sh` | Modify — remove env var gates, add retention cleanup, read custom jobs | 1, 5, 7 |
| `plugin/skills/init/init.md` | Modify — remove Step 7b, add activator cleanup | 1, 3 |
| `plugin/skills/schedule/schedule.md` | Modify — remove env var refs, add `add` subcommand, file-based pause | 1, 7 |
| `plugin/skills/retrieve/retrieve.md` | Modify — use cursor script | 4 |
| `plugin/skills/analyze/analyze.md` | Modify — remove retention prose | 5 |
| `plugin/scripts/update-cursor.sh` | Create — atomic cursor persistence | 4 |
| `config/ingest-template.yaml` | Modify — add `schedule` section, remove env var docs | 1, 7 |
| `install.sh` | Modify — add activator cleanup step | 3 |
| `plugin/skills/doctor/doctor.md` | Modify — call `lcm_health()` when available | (prep for Gap 6 RFC) |

---

## Verification

1. Fresh install → session starts → cron jobs registered without any env vars set
2. `/xgh-schedule pause` → next session → no crons registered, output shows "paused"
3. `/xgh-schedule resume` → next session → crons registered normally
4. No `continuous-learning-activator.sh` or `cipher_*` references in `.claude/hooks/`
5. Run `/xgh-retrieve` → `.cursors.json` updated atomically with latest timestamps
6. Create 10 test files in `~/.xgh/inbox/processed/` with old dates → session start → files deleted
7. Add custom job to `ingest.yaml` → session start → job registered via CronCreate
8. `/xgh-schedule add "/xgh-brief" "0 8 * * 1-5"` → persisted in ingest.yaml, registered immediately

---

## What does NOT change

- `lcm_*` API surface — untouched
- Context tree loading — untouched
- RTK hook integration — untouched
- context-mode health tracking — untouched
- Skill content (except retrieve/analyze/schedule/init/doctor) — untouched
