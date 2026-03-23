---
name: xgh:schedule
description: "This skill should be used when the user runs /xgh-schedule or asks to check, pause, resume, or manage the scheduler, or asks about skill mode preferences. Interactive scheduler control panel — lists, pauses, resumes, and fires xgh CronCreate jobs. Also manages ~/.xgh/prefs.json skill execution mode preferences."
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
| `pause morning` | → **Pause** command-center morning briefing |
| `pause pulse` | → **Pause** command-center pulse |
| `resume retrieve` | → **Resume** retrieve |
| `resume analyze` | → **Resume** analyze |
| `resume morning` | → **Resume** command-center morning briefing |
| `resume pulse` | → **Resume** command-center pulse |
| `run retrieve` | → **Run** retrieve now |
| `run analyze` | → **Run** analyze now |
| `off` | → **Off** (cancel all) |
| `prefs reset <skill>` | → **Reset pref** for skill |
| `prefs` | → **Show prefs** |
| `add "<skill>" "<cron>"` | → **Add** custom job |
| `pause` (no args) | → **Pause all** (touch ~/.xgh/scheduler-paused) |
| `resume` (no args) | → **Resume all** (rm ~/.xgh/scheduler-paused) |

---

## Status

Call CronList. Find jobs where prompt matches `retrieve-bash`, `retrieve-mcp`, `/xgh-analyze`, `/xgh-command-center morning`, or `/xgh-command-center pulse`.

If 0 matching jobs found:
> ⚠️ No active xgh scheduler jobs. Run `/xgh-schedule resume` to enable.

If jobs found, display:

```
## 🐴🤖 xgh schedule

| Job | Cron | Status | Note |
|-----|------|--------|------|
| retrieve-bash | */5 * * * * | ✅ active | auto-expires in 3 days |
| retrieve-mcp | */5 * * * * | ✅ active | auto-expires in 3 days |
| analyze | */30 * * * * | ✅ active | auto-expires in 3 days |
| command-center morning | 0 8 * * 1-5 | ✅ active | weekdays 8am |
| command-center pulse | */15 * * * * | ✅ active | every 15 min |

Providers: N bash, M mcp (total)
```

Note: CronCreate jobs auto-expire after 3 days. They are re-created automatically on the next session start unless paused (`~/.xgh/scheduler-paused` exists).

Command-center cron jobs are registered by `/xgh-command-center` on first run.

---

## Pause

Call CronDelete for the job whose prompt matches the target (`retrieve-bash`, `retrieve-mcp`, or `/xgh-analyze`).

`pause retrieve` deletes both `retrieve-bash` and `retrieve-mcp` jobs.

To find the job ID: scan CronList output for the matching prompt, extract the job ID.

Report: `⏸ retrieve paused. Resume with /xgh-schedule resume retrieve.`

---

## Resume

Call CronCreate:
- retrieve-bash: `cron: "*/5 * * * *"`, `prompt: "bash ~/.xgh/scripts/retrieve-all.sh || true"`, `recurring: true`
- retrieve-mcp: `cron: "*/5 * * * *"`, `prompt: "Read all provider.yaml in ~/.xgh/user_providers/. For each with mode: mcp, call MCP tools per spec, write inbox items, update cursors."`, `recurring: true` — **only register if at least one `mode: mcp` provider exists**
- analyze: `cron: "*/30 * * * *"`, `prompt: "/xgh-analyze"`, `recurring: true`
- morning: `cron: "0 8 * * 1-5"`, `prompt: "/xgh-command-center morning"`, `recurring: true`
- pulse: `cron: "*/15 * * * *"`, `prompt: "/xgh-command-center pulse"`, `recurring: true`

Report: `✅ retrieve resumed (*/5 * * * *).`

---

## Run

Invoke the target skill directly in this session (not via cron):
- `run retrieve` → run `bash ~/.xgh/scripts/retrieve-all.sh` AND invoke the MCP fetch prompt (read all `provider.yaml` in `~/.xgh/user_providers/`, for each with `mode: mcp` call MCP tools per spec, write inbox items, update cursors)
- `run analyze` → invoke `/xgh-analyze`

---

## Off

Call CronDelete for all jobs (`retrieve-bash`, `retrieve-mcp`, `/xgh-analyze`, and command-center jobs). Report count of jobs cancelled.

---

## Add

Append a custom job to `~/.xgh/ingest.yaml`:

```bash
python3 -c "
import yaml, sys, os
skill, cron = sys.argv[1], sys.argv[2]
path = os.path.expanduser('~/.xgh/ingest.yaml')
with open(path) as f:
    cfg = yaml.safe_load(f) or {}
jobs = cfg.setdefault('schedule', {}).setdefault('jobs', [])
jobs = [j for j in jobs if j.get('skill') != skill]
jobs.append({'skill': skill, 'cron': cron})
cfg['schedule']['jobs'] = jobs
with open(path, 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False)
print(f'Added: {skill} at {cron}')
" "<skill>" "<cron>"
```

Then register immediately via CronCreate: `cron: "<cron>"`, `prompt: "<skill>"`, `recurring: true`.

Report: `✅ Added <skill> (<cron>). Persisted in ingest.yaml — will auto-register on future sessions.`

---

## Pause all

When `pause` is called with no specific job name:

```bash
touch ~/.xgh/scheduler-paused
```

Cancel all active CronCreate jobs via CronDelete.

Report: `⏸ All scheduled jobs paused. Resume with /xgh-schedule resume.`

---

## Resume all

When `resume` is called with no specific job name:

```bash
rm -f ~/.xgh/scheduler-paused
```

Re-register default crons + custom jobs from ingest.yaml.

Report: `✅ Scheduler resumed. Jobs will re-register on next session start.`

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

---

## Schedule-event trigger evaluation

During each scheduled retrieve/analyze cycle, evaluate `source: schedule` triggers.

1. Read `~/.xgh/triggers.yaml` — if `enabled: false`, skip entirely.
2. Read all `~/.xgh/triggers/*.yaml` where `when.source: schedule`.
3. For each schedule trigger:
   a. Parse the `cron:` expression (standard 5-field: min hour dom mon dow).
   b. Check if the expression matches the current time (within the run window).
      A cron matches if it would have fired in the last `retrieve_interval` minutes.
   c. Check cooldown/backoff (same logic as standard path — see xgh:trigger skill).
   d. If matched and cooldown clear: execute `then:` steps.
   e. Update `.state.json`.
4. Log: `Schedule triggers: N evaluated, K fired`

**Cron evaluation note:** Use a simple check — compare cron fields against current
`date` output. For `0 9 * * MON`: fire if current hour=9, minute<5, weekday=Monday.
Exact match within the retrieve window (5min) is sufficient; cron-exact precision
is not required for this use case.
