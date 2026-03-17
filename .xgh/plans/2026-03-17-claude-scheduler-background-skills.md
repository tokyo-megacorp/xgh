# Claude-Internal Scheduler & Background Skill Execution — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace OS-level launchd/cron with Claude's built-in CronCreate for session-scoped scheduling, and add a preference-gated background-agent execution mode to interactive skills.

**Architecture:** Session-start hook injects `schedulerTrigger` + explicit CronCreate instructions into `additionalContext`; Claude creates two recurring cron jobs at session start when enabled. A new `/xgh-schedule` control panel manages jobs. Interactive skills gain a Python3-based preamble that reads/writes `~/.xgh/prefs.json` to remember each skill's execution mode.

**Tech Stack:** Bash, Python 3 (hook inline), Markdown (skill instructions), JSON (`~/.xgh/prefs.json`), Claude Code CronCreate/CronDelete/CronList/Agent tools.

---

## File Map

| File | Action |
|---|---|
| `plugin/hooks/session-start.sh` | Modify — add `XGH_SCHEDULER` env var, `schedulerTrigger` + instructions in JSON output |
| `tests/test-hooks.sh` | Modify — add `schedulerTrigger` assertions |
| `plugin/commands/schedule.md` | Create — `/xgh-schedule` slash command |
| `plugin/skills/schedule/schedule.md` | Create — schedule control panel skill |
| `plugin/skills/retrieve/retrieve.md` | Modify — update trigger text, enforce one-line summary discipline |
| `plugin/skills/analyze/analyze.md` | Modify — same |
| `plugin/skills/briefing/briefing.md` | Modify — same |
| `plugin/skills/investigate/investigate.md` | Modify — add preamble |
| `plugin/skills/implement/implement.md` | Modify — add preamble |
| `plugin/skills/index/index.md` | Modify — add preamble |
| `plugin/skills/track/track.md` | Modify — add preamble |
| `plugin/skills/collab/collab.md` | Modify — add preamble |
| `plugin/commands/retrieve.md` | Modify — update scheduler reference text |
| `plugin/commands/analyze.md` | Modify — update scheduler reference text |
| `install.sh` | Modify — run `ingest-schedule.sh uninstall`, remove scheduler install block |
| `scripts/ingest-schedule.sh` | Delete |
| `scripts/schedulers/com.xgh.retriever.plist` | Delete |
| `scripts/schedulers/com.xgh.analyzer.plist` | Delete |
| `techpack.yaml` | Modify — remove `ingest-schedule` component |

---

## Task 1: Add schedulerTrigger to session-start hook

**Files:**
- Modify: `plugin/hooks/session-start.sh`
- Modify: `tests/test-hooks.sh`

### Background

The session-start hook is a Bash script that outputs JSON. Claude Code injects this JSON as `additionalContext` and Claude reads it. When `schedulerTrigger` is `"on"`, Claude needs explicit instruction text telling it to call CronCreate — a bare `"schedulerTrigger": "on"` key alone is not enough. We add an `schedulerInstructions` field with imperative text.

Pattern to follow: the existing `briefingTrigger` field (line 50 and 131 in `plugin/hooks/session-start.sh`).

- [ ] **Step 1: Write the failing test**

Add these assertions to `tests/test-hooks.sh` (after the existing `briefingTrigger` tests, before the `prompt-submit` section):

```bash
# Validate schedulerTrigger=off by default
SS_SCHED_DEFAULT=$(XGH_CONTEXT_TREE="$TMPDIR_CT" bash hooks/session-start.sh)
SS_ST_DEFAULT=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d.get('schedulerTrigger', ''))
" "$SS_SCHED_DEFAULT")
assert_eq "schedulerTrigger default=off" "$SS_ST_DEFAULT" "off"

# Validate schedulerTrigger=on when XGH_SCHEDULER=on
SS_SCHED_ON=$(XGH_CONTEXT_TREE="$TMPDIR_CT" XGH_SCHEDULER="on" bash hooks/session-start.sh)
SS_ST_ON=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d.get('schedulerTrigger', ''))
" "$SS_SCHED_ON")
assert_eq "schedulerTrigger on" "$SS_ST_ON" "on"

# Validate schedulerInstructions present when on
SS_SI=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
v = d.get('schedulerInstructions', '')
print('yes' if v and '/xgh-retrieve' in v and '/xgh-analyze' in v else 'no:' + repr(v))
" "$SS_SCHED_ON")
assert_eq "schedulerInstructions contains cron prompts" "$SS_SI" "yes"

# Validate schedulerInstructions absent (null) when off
SS_SI_OFF=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print('null' if d.get('schedulerInstructions') is None else 'present')
" "$SS_SCHED_DEFAULT")
assert_eq "schedulerInstructions null when off" "$SS_SI_OFF" "null"
```

- [ ] **Step 2: Run failing test**

```bash
cd tests && bash test-hooks.sh 2>&1 | tail -15
```

Expected: 4 new FAILs about `schedulerTrigger` and `schedulerInstructions`.

- [ ] **Step 3: Add XGH_SCHEDULER to the hook**

In `plugin/hooks/session-start.sh`, after line 8 (`XGH_BRIEFING="${XGH_BRIEFING:-off}"`), add:

```bash
XGH_SCHEDULER="${XGH_SCHEDULER:-off}"
```

- [ ] **Step 4: Add scheduler logic to the Python block**

In `plugin/hooks/session-start.sh`, inside the `python3 << 'PYEOF'` block, after the `briefing_trigger` computation (after line 36, before `decision_table`), add:

```python
scheduler_env = os.environ.get("XGH_SCHEDULER", "off")
scheduler_trigger = "on" if scheduler_env in ("on", "1") else "off"

if scheduler_trigger == "on":
    scheduler_instructions = (
        "SCHEDULER — act on this immediately and silently, no confirmation needed: "
        "Call CronCreate twice to set up background jobs for this session: "
        "(1) cron='*/5 * * * *', prompt='/xgh-retrieve', recurring=true  "
        "(2) cron='*/30 * * * *', prompt='/xgh-analyze', recurring=true  "
        "These will auto-expire after 3 days. Use /xgh-schedule to manage them."
    )
else:
    scheduler_instructions = None
```

- [ ] **Step 5: Add fields to both JSON output blocks**

There are two `output = {...}` dicts in the hook (one for the no-context-tree path at line ~50, one for the main path at line ~131). Add to **both**:

```python
"schedulerTrigger": scheduler_trigger,
"schedulerInstructions": scheduler_instructions,
```

The no-context-tree output block becomes:
```python
output = {
    "result": "xgh: session-start loaded 0 context files",
    "contextFiles": [],
    "decisionTable": decision_table,
    "briefingTrigger": briefing_trigger,
    "schedulerTrigger": scheduler_trigger,
    "schedulerInstructions": scheduler_instructions,
}
```

- [ ] **Step 6: Run tests and verify passing**

```bash
cd tests && bash test-hooks.sh 2>&1 | tail -5
```

Expected: `Hooks test: N passed, 0 failed`

- [ ] **Step 7: Also run install tests to verify no regressions**

```bash
bash tests/test-install.sh 2>&1 | tail -3
```

Expected: `Install test: 38 passed, 0 failed`

- [ ] **Step 8: Commit**

```bash
git add plugin/hooks/session-start.sh tests/test-hooks.sh
git commit -m "feat: add schedulerTrigger to session-start hook (XGH_SCHEDULER=on)"
```

---

## Task 2: Create /xgh-schedule control panel

**Files:**
- Create: `plugin/commands/schedule.md`
- Create: `plugin/skills/schedule/schedule.md`

### Background

The schedule skill is a short, always-interactive skill that lets the user manage the CronCreate jobs. It uses CronList to find existing jobs by matching the exact prompt strings `/xgh-retrieve` and `/xgh-analyze`. It handles the 3-day expiry edge case by detecting 0 jobs and offering to re-create them.

- [ ] **Step 1: Create the command file**

Create `plugin/commands/schedule.md`:

```markdown
---
name: xgh-schedule
description: Manage xgh background scheduler — list, pause, resume, or run retrieve/analyze jobs. Also manage per-skill execution mode preferences.
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh schedule`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status.

# /xgh-schedule — Scheduler Control Panel

Run the `xgh:schedule` skill to manage the session scheduler and skill execution preferences.

## Usage

```
/xgh-schedule                        # show active jobs
/xgh-schedule pause retrieve         # pause retrieve job
/xgh-schedule pause analyze          # pause analyze job
/xgh-schedule resume retrieve        # resume retrieve job
/xgh-schedule resume analyze         # resume analyze job
/xgh-schedule run retrieve           # fire retrieve immediately
/xgh-schedule run analyze            # fire analyze immediately
/xgh-schedule off                    # cancel all xgh jobs this session
/xgh-schedule prefs                  # show skill mode preferences
/xgh-schedule prefs reset <skill>    # clear saved preference for a skill
```

## Enable auto-scheduling

Set `XGH_SCHEDULER=on` in your shell environment or `CLAUDE.local.md` to auto-create jobs at each session start.
```

- [ ] **Step 2: Create the skill file**

Create `plugin/skills/schedule/schedule.md`:

```markdown
---
name: xgh:schedule
description: Interactive scheduler control panel. Lists, pauses, resumes, and fires xgh CronCreate jobs. Also manages ~/.xgh/prefs.json skill execution mode preferences.
type: flexible
triggers:
  - /xgh-schedule command
  - when user asks to check, pause, resume, or manage the scheduler
  - when user asks about skill mode preferences
---

> **Output format:** Start with `## 🐴🤖 xgh schedule`. Use ✅ ⚠️ ❌ for status. Keep output concise.

# xgh:schedule — Scheduler Control Panel

## Routing

Parse the invocation text to determine the subcommand:

| Invocation pattern | Action |
|---|---|
| no args or `status` | → **Status** |
| `pause retrieve` | → **Pause** retrieve |
| `pause analyze` | → **Pause** analyze |
| `resume retrieve` | → **Resume** retrieve |
| `resume analyze` | → **Resume** analyze |
| `run retrieve` | → **Run** retrieve now |
| `run analyze` | → **Run** analyze now |
| `off` | → **Off** (cancel all) |
| `prefs reset <skill>` | → **Reset pref** for skill |
| `prefs` | → **Show prefs** |

---

## Status

Call CronList. Find jobs where prompt is exactly `/xgh-retrieve` or `/xgh-analyze`.

If 0 matching jobs found:
> ⚠️ No active xgh scheduler jobs. Enable with `XGH_SCHEDULER=on` or run `/xgh-schedule resume retrieve` and `/xgh-schedule resume analyze`.

If jobs found, display:

```
## 🐴🤖 xgh schedule

| Job | Cron | Status | Note |
|-----|------|--------|------|
| retrieve | */5 * * * * | ✅ active | auto-expires in 3 days |
| analyze | */30 * * * * | ✅ active | auto-expires in 3 days |
```

Note: CronCreate jobs auto-expire after 3 days. They are re-created automatically on the next session start if `XGH_SCHEDULER=on`.

---

## Pause

Call CronDelete for the job whose prompt matches the target (`/xgh-retrieve` or `/xgh-analyze`).

To find the job ID: scan CronList output for the matching prompt, extract the job ID.

Report: `⏸ retrieve paused. Resume with /xgh-schedule resume retrieve.`

---

## Resume

Call CronCreate:
- retrieve: `cron: "*/5 * * * *"`, `prompt: "/xgh-retrieve"`, `recurring: true`
- analyze: `cron: "*/30 * * * *"`, `prompt: "/xgh-analyze"`, `recurring: true`

Report: `✅ retrieve resumed (*/5 * * * *).`

---

## Run

Invoke the target skill directly in this session (not via cron):
- `run retrieve` → invoke `/xgh-retrieve`
- `run analyze` → invoke `/xgh-analyze`

---

## Off

Call CronDelete for both jobs. Report count of jobs cancelled.

---

## Show prefs

Read `~/.xgh/prefs.json` using Bash:
```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.xgh/prefs.json')
try:
    p = json.load(open(path))
    sm = p.get('skill_mode', {})
    if not sm:
        print('(no preferences saved yet)')
    else:
        for k, v in sm.items():
            mode = v.get('mode', '?')
            auto = v.get('autonomy', '')
            print(f'  {k}: {mode}' + (f' / {auto}' if auto else ''))
except FileNotFoundError:
    print('(no preferences saved yet)')
"
```

Display the output in a table.

---

## Reset pref

Delete the preference entry for the named skill:

```bash
python3 -c "
import json, os, sys
skill = sys.argv[1]
path = os.path.expanduser('~/.xgh/prefs.json')
try:
    p = json.load(open(path))
    p.get('skill_mode', {}).pop(skill, None)
    json.dump(p, open(path, 'w'), indent=2)
    print(f'Reset: {skill} will prompt on next invocation.')
except FileNotFoundError:
    print('Nothing to reset.')
" "<skill_name>"
```
```

- [ ] **Step 3: Verify files exist and are well-formed**

```bash
python3 -c "
import re
for f in ['plugin/commands/schedule.md', 'plugin/skills/schedule/schedule.md']:
    text = open(f).read()
    assert '---' in text, f'{f} missing frontmatter'
    assert 'name:' in text, f'{f} missing name'
    print(f'OK: {f}')
"
```

Expected: `OK: plugin/commands/schedule.md` and `OK: plugin/skills/schedule/schedule.md`

- [ ] **Step 4: Commit**

```bash
git add plugin/commands/schedule.md plugin/skills/schedule/schedule.md
git commit -m "feat: add /xgh-schedule control panel skill and command"
```

---

## Task 3: Remove OS scheduler artifacts

**Files:**
- Modify: `install.sh`
- Modify: `techpack.yaml`
- Delete: `scripts/ingest-schedule.sh`
- Delete: `scripts/schedulers/com.xgh.retriever.plist`
- Delete: `scripts/schedulers/com.xgh.analyzer.plist`
- Modify: `plugin/commands/retrieve.md`
- Modify: `plugin/commands/analyze.md`

### Background

The install.sh has a scheduler block around lines 1117–1145 that copies plist templates and calls `ingest-schedule.sh install`. Before deleting the script, the installer must call `ingest-schedule.sh uninstall` to clean up any previously installed launchd agents on existing installations. The `com.xgh.models.plist` (vllm-mlx daemon) is NOT deleted — it is out of scope.

- [ ] **Step 1: Write the install test for scheduler cleanup**

Add to `tests/test-install.sh` (after the existing assertions):

```bash
# Verify scheduler scripts are NOT installed (replaced by CronCreate)
assert_not_contains "CLAUDE.local.md" "ingest-schedule"
# Verify techpack has no ingest-schedule component
assert_not_contains "${XGH_LOCAL_PACK}/techpack.yaml" "ingest-schedule"
```

- [ ] **Step 2: Run the failing test**

```bash
bash tests/test-install.sh 2>&1 | tail -5
```

Expected: 1–2 new FAILs about `ingest-schedule`.

- [ ] **Step 3: Remove ingest-schedule component from techpack.yaml**

In `techpack.yaml`, delete the entire `ingest-schedule` component block:

```yaml
  - id: ingest-schedule
    type: script
    source: scripts/ingest-schedule.sh
    description: "Install/uninstall xgh ingest scheduler — launchd on macOS, cron on Linux"
```

- [ ] **Step 4: Update install.sh — run uninstall before removing**

Locate the scheduler install block in `install.sh` (around line 1117, inside `lane "Scheduling ⏰"` or similar). Replace the entire block with:

```bash
# ── Migrate: unload any previously installed OS-level scheduler ──────────────
if [ -f "$HOME/.xgh/lib/ingest-schedule.sh" ]; then
  info "Unloading legacy OS scheduler (replaced by Claude-internal CronCreate)..."
  bash "$HOME/.xgh/lib/ingest-schedule.sh" uninstall 2>/dev/null || true
  rm -f "$HOME/.xgh/lib/ingest-schedule.sh"
  info "Legacy scheduler removed. Enable session scheduling with XGH_SCHEDULER=on."
fi
```

Also update the output text near line 1188: replace
```bash
echo -e "  ${DIM}Models run automatically as a daemon (launchd/systemd).${NC}"
```
with:
```bash
echo -e "  ${DIM}Background jobs run each Claude session. Set XGH_SCHEDULER=on to enable.${NC}"
```

- [ ] **Step 5: Delete the OS scheduler files**

```bash
rm scripts/ingest-schedule.sh
rm scripts/schedulers/com.xgh.retriever.plist
rm scripts/schedulers/com.xgh.analyzer.plist
# Do NOT delete com.xgh.models.plist — out of scope
```

- [ ] **Step 6: Update retrieve and analyze command docs**

In `plugin/commands/retrieve.md`, replace:
```
- Invoked automatically by the scheduler (launchd/cron). You can also run it manually to test.
```
with:
```
- Invoked automatically each Claude session via CronCreate when `XGH_SCHEDULER=on`. Also run manually to test.
```

In `plugin/commands/analyze.md`, replace:
```
- Invoked automatically by the scheduler (launchd/cron).
```
with:
```
- Invoked automatically each Claude session via CronCreate when `XGH_SCHEDULER=on`.
```

Also update the `description` frontmatter in `plugin/skills/retrieve/retrieve.md` and `plugin/skills/analyze/analyze.md`: replace `launchd/cron` with `CronCreate`.

- [ ] **Step 7: Run all tests**

```bash
bash tests/test-install.sh 2>&1 | tail -3
bash tests/test-hooks.sh 2>&1 | tail -3
bash tests/test-techpack.sh 2>&1 | tail -3
```

Expected: all passing, 0 failed.

- [ ] **Step 8: Commit**

```bash
git add install.sh techpack.yaml plugin/commands/retrieve.md plugin/commands/analyze.md \
  plugin/skills/retrieve/retrieve.md plugin/skills/analyze/analyze.md \
  tests/test-install.sh
git rm scripts/ingest-schedule.sh scripts/schedulers/com.xgh.retriever.plist scripts/schedulers/com.xgh.analyzer.plist
git commit -m "feat: remove OS scheduler, replace with Claude-internal CronCreate"
```

---

## Task 4: Update headless skills — output discipline

**Files:**
- Modify: `plugin/skills/retrieve/retrieve.md`
- Modify: `plugin/skills/analyze/analyze.md`
- Modify: `plugin/skills/briefing/briefing.md`

### Background

When CronCreate fires `/xgh-retrieve`, it runs in the main session turn. To keep context clean, the skill must end with a single summary line — not stream raw tool output. The existing skills already call for `ctx_execute` for Bash processing, but there is no explicit "end with one-line summary" rule. Add it.

Note: the retrieve/analyze skills also have stale references to `launchd/cron` in their `triggers` frontmatter and body text — update these in this task.

- [ ] **Step 1: Test that the one-line summary rule exists**

```bash
grep -q "one-line summary\|single summary line\|one line\|one paragraph" \
  plugin/skills/retrieve/retrieve.md && echo "OK: retrieve" || echo "MISSING: retrieve"
grep -q "one-line summary\|single summary line\|one line\|one paragraph" \
  plugin/skills/analyze/analyze.md && echo "OK: analyze" || echo "MISSING: analyze"
grep -q "one-line summary\|single summary line\|one line\|one paragraph" \
  plugin/skills/briefing/briefing.md && echo "OK: briefing" || echo "MISSING: briefing"
```

Expected: all three `MISSING`.

- [ ] **Step 2: Add output discipline section to retrieve.md**

In `plugin/skills/retrieve/retrieve.md`:

a) Update frontmatter `triggers` — replace `launchd or cron` with `CronCreate`:
```yaml
triggers:
  - when invoked via /xgh-retrieve command
  - when invoked by CronCreate (session scheduler, XGH_SCHEDULER=on)
```

b) Update the "Invoked headlessly" code block at the top — replace the `claude -p` block with:
```
Invoked by CronCreate:
  prompt: /xgh-retrieve
  cron: */5 * * * *
  recurring: true
```

c) At the very end of the file, add a new section:

```markdown
## Output discipline

This skill runs in the main session turn (triggered by CronCreate or manually). To preserve context:

1. Route ALL Bash/Python processing through `ctx_execute` or `ctx_batch_execute` when context-mode is available.
2. Never print raw inbox content, message bodies, or full API responses to the session.
3. **End every run with exactly one summary line:**
   ```
   Retrieve complete: <N> new items stashed, <M> critical, <K> channels scanned.
   ```
   Nothing else after this line.
```

- [ ] **Step 3: Add output discipline section to analyze.md**

Same pattern. Update frontmatter `triggers`:
```yaml
triggers:
  - when invoked via /xgh-analyze command
  - when invoked by CronCreate (session scheduler, XGH_SCHEDULER=on)
  - when ~/.xgh/inbox/.urgent exists (triggered by retriever on critical items)
```

Replace `claude -p` block with:
```
Invoked by CronCreate:
  prompt: /xgh-analyze
  cron: */30 * * * *
  recurring: true
```

Add at end:
```markdown
## Output discipline

1. Route ALL classification, dedup, and digest processing through `ctx_execute` when available.
2. Never dump raw inbox content into session context.
3. **End every run with exactly one summary line:**
   ```
   Analyze complete: <N> items processed, <M> stored, <K> duplicates skipped.
   ```
```

- [ ] **Step 4: Add output discipline to briefing.md**

At the end of `plugin/skills/briefing/briefing.md`, add:

```markdown
## Output discipline

When invoked by CronCreate or as a background task:
1. Route all MCP fetches through `ctx_batch_execute` when context-mode is available.
2. Return the briefing summary inline — concise, structured, no raw API payloads.
```

- [ ] **Step 5: Run the grep test again — verify all passing**

```bash
grep -q "one-line summary\|Output discipline" plugin/skills/retrieve/retrieve.md && echo "OK: retrieve" || echo "MISSING: retrieve"
grep -q "one-line summary\|Output discipline" plugin/skills/analyze/analyze.md && echo "OK: analyze" || echo "MISSING: analyze"
grep -q "Output discipline" plugin/skills/briefing/briefing.md && echo "OK: briefing" || echo "MISSING: briefing"
```

Expected: all `OK`.

- [ ] **Step 6: Commit**

```bash
git add plugin/skills/retrieve/retrieve.md plugin/skills/analyze/analyze.md plugin/skills/briefing/briefing.md
git commit -m "feat: add output discipline to headless skills (retrieve, analyze, briefing)"
```

---

## Task 5: Add execution mode preamble to investigate + implement

**Files:**
- Modify: `plugin/skills/investigate/investigate.md`
- Modify: `plugin/skills/implement/implement.md`

### Background

The preamble is a new section added **before** the existing skill content. It reads `~/.xgh/prefs.json`, prompts once if unset, writes the preference, and routes to background-agent or interactive dispatch. Uses Python3 (not jq — already available in all xgh environments per the hooks). Flag overrides are text-matched (not parsed), consistent with how Claude Code slash commands work.

The preamble is identical across all interactive skills except for the `<skill_name>` placeholder. Implement it exactly as specified here — no shortcuts.

- [ ] **Step 1: Test that preamble is absent (baseline)**

```bash
grep -q "Preamble\|prefs.json\|skill_mode" plugin/skills/investigate/investigate.md \
  && echo "ALREADY_PRESENT: investigate" || echo "OK_ABSENT: investigate"
grep -q "Preamble\|prefs.json\|skill_mode" plugin/skills/implement/implement.md \
  && echo "ALREADY_PRESENT: implement" || echo "OK_ABSENT: implement"
```

Expected: both `OK_ABSENT`.

- [ ] **Step 2: Add preamble to investigate.md**

Insert the following **immediately after the closing `---` of the frontmatter** (before `# xgh:investigate`):

```markdown
## Preamble — Execution mode

Before starting, check whether the user has a saved execution mode preference for this skill.

**Step P1 — Read preference:**
```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.xgh/prefs.json')
try:
    p = json.load(open(path))
    v = p.get('skill_mode', {}).get('investigate')
    print(json.dumps(v) if v else '')
except: print('')
"
```
If output is non-empty JSON, extract `mode` and `autonomy` (if present) and skip to **Dispatch** below.

**Step P2 — If not set, ask the user (one question at a time):**
- "Run **investigate** in background (returns summary when done) or interactive? [b/i, default: i]"
- If "b": "Check in with a quick question before starting, or fire-and-forget? [c/f, default: c]"

**Step P3 — Write preference:**
```bash
python3 -c "
import json, os, sys
mode, autonomy = sys.argv[1], sys.argv[2]
path = os.path.expanduser('~/.xgh/prefs.json')
os.makedirs(os.path.dirname(path), exist_ok=True)
try: p = json.load(open(path))
except: p = {}
p.setdefault('skill_mode', {})
entry = {'mode': mode} if mode == 'interactive' else {'mode': mode, 'autonomy': autonomy}
p['skill_mode']['investigate'] = entry
json.dump(p, open(path, 'w'), indent=2)
" "<mode>" "<autonomy>"
```

**Step P4 — Flag overrides** (check the raw invocation text; do not update prefs.json):
- contains `--bg` → use background mode
- contains `--interactive` or `--fg` → use interactive mode
- contains `--checkin` → use check-in autonomy
- contains `--auto` → use fire-and-forget autonomy
- contains `--reset` → run `python3 -c "import json,os; p=json.load(open(os.path.expanduser('~/.xgh/prefs.json'))); p.get('skill_mode',{}).pop('investigate',None); json.dump(p,open(os.path.expanduser('~/.xgh/prefs.json'),'w'),indent=2)"` then re-prompt

**Dispatch:**

**Interactive mode** → proceed with the skill normally (continue to the rest of this file).

**Background / check-in mode:**
1. Ask at most 2 essential clarifying questions in the main session.
2. Collect context: user's request verbatim, current branch (`git branch --show-current`), recent log (`git log --oneline -5`), any relevant file paths mentioned.
3. Dispatch via Agent tool with `run_in_background: true`. Prompt must be fully self-contained.
4. Reply: "Investigation running in background — I'll post findings when done."
5. When agent completes: post a ≤5-bullet summary to main session.

**Background / fire-and-forget mode:**
1. Collect context automatically (no questions).
2. Dispatch via Agent tool with `run_in_background: true`.
3. Reply: "Investigation running in background — I'll post findings when done."
4. When agent completes: post a ≤5-bullet summary.

---
```

- [ ] **Step 3: Add identical preamble to implement.md**

Insert the same preamble block after implement.md's frontmatter closing `---`, replacing `investigate` with `implement` in all occurrences (the skill name, the question text, the Python script argument, and the `--reset` inline command).

Key replacements:
- `"Run **investigate**` → `"Run **implement**`
- `'investigate'` in Python → `'implement'`
- `p['skill_mode']['investigate']` → `p['skill_mode']['implement']`

- [ ] **Step 4: Verify preamble was inserted**

```bash
grep -c "Preamble\|prefs.json\|skill_mode" plugin/skills/investigate/investigate.md
grep -c "Preamble\|prefs.json\|skill_mode" plugin/skills/implement/implement.md
```

Expected: each file should have ≥ 5 matching lines.

- [ ] **Step 5: Commit**

```bash
git add plugin/skills/investigate/investigate.md plugin/skills/implement/implement.md
git commit -m "feat: add execution mode preamble to investigate and implement skills"
```

---

## Task 6: Add execution mode preamble to index, track, collab

**Files:**
- Modify: `plugin/skills/index/index.md`
- Modify: `plugin/skills/track/track.md`
- Modify: `plugin/skills/collab/collab.md`

### Background

Same preamble as Task 5, applied to three more skills. Exact same pattern — only the skill name changes in the Python scripts and question text.

- [ ] **Step 1: Verify all three are missing preamble**

```bash
for skill in index track collab; do
  grep -q "Preamble\|prefs.json" "plugin/skills/$skill/$skill.md" \
    && echo "ALREADY_PRESENT: $skill" || echo "OK_ABSENT: $skill"
done
```

Expected: all `OK_ABSENT`.

- [ ] **Step 2: Add preamble to index.md**

Insert preamble after the frontmatter `---` in `plugin/skills/index/index.md`. Replace all `investigate` occurrences with `index`.

- [ ] **Step 3: Add preamble to track.md**

Insert preamble after the frontmatter `---` in `plugin/skills/track/track.md`. Replace all `investigate` with `track`.

- [ ] **Step 4: Add preamble to collab.md**

Insert preamble after the frontmatter `---` in `plugin/skills/collab/collab.md`. Replace all `investigate` with `collab`.

- [ ] **Step 5: Verify all three**

```bash
for skill in index track collab; do
  count=$(grep -c "Preamble\|prefs.json\|skill_mode" "plugin/skills/$skill/$skill.md" 2>/dev/null || echo 0)
  [ "$count" -ge 5 ] && echo "OK: $skill ($count matches)" || echo "FAIL: $skill ($count matches)"
done
```

Expected: all `OK` with ≥5 matches each.

- [ ] **Step 6: Run full test suite**

```bash
bash tests/test-install.sh 2>&1 | tail -3
bash tests/test-hooks.sh 2>&1 | tail -3
bash tests/test-techpack.sh 2>&1 | tail -3
bash tests/test-config.sh 2>&1 | tail -3
```

Expected: all suites passing, 0 failures.

- [ ] **Step 7: Final commit**

```bash
git add plugin/skills/index/index.md plugin/skills/track/track.md plugin/skills/collab/collab.md
git commit -m "feat: add execution mode preamble to index, track, and collab skills"
```
