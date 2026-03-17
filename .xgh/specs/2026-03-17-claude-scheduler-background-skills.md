# Claude-Internal Scheduler & Background Skill Execution

> **For agentic workers:** Use superpowers:subagent-driven-development to implement this plan.

**Goal:** Replace OS-level cron/launchd with Claude's built-in CronCreate for session-scoped scheduling, and give each xgh skill the ability to run as a background Agent with per-skill execution mode preferences.

**Architecture:** Session-start hook injects a `schedulerTrigger` flag into `additionalContext`; Claude reads this flag from the injected instructions and calls CronCreate to set up retrieve/analyze jobs. A new `/xgh-schedule` command is the interactive control panel. Headless skills run directly in the main session when triggered by CronCreate (no extra sub-agent layer). Interactive skills check `~/.xgh/prefs.json` on invocation and prompt the user once to capture mode + autonomy preferences.

**Tech Stack:** Bash (hook), Python (hook inline script), Markdown (skill instructions), JSON (`~/.xgh/prefs.json`), Claude Code CronCreate/CronDelete/CronList/Agent tools.

---

## 1. Session-scoped Scheduler

### 1.1 How the trigger mechanism works

The session-start hook is a **Bash script** that outputs JSON. It cannot call Claude tools — it only injects data. The scheduling trigger is two-part:

**Part A — Hook injects the flag (Bash side):**

The hook's inline Python script already builds a JSON payload including `briefingTrigger`. Add parallel logic for `schedulerTrigger`:

```python
scheduler_env = os.environ.get("XGH_SCHEDULER", "off")
scheduler_trigger = "on" if scheduler_env in ("on", "1") else "off"
```

When `scheduler_trigger = "on"`, the payload includes both the flag and **explicit text instructions** in the `additionalContext` output that Claude reads:

```
schedulerTrigger: on

SCHEDULER INSTRUCTIONS (act on this now):
Call CronCreate twice to set up background jobs for this session:
1. cron: "*/5 * * * *", prompt: "/xgh-retrieve", recurring: true
2. cron: "*/30 * * * *", prompt: "/xgh-analyze", recurring: true
These fire automatically. No confirmation needed — just create them silently.
```

**Part B — Claude acts on the instruction (Claude side):**

Claude reads the injected `additionalContext`, sees the scheduler instructions, and calls CronCreate. This is exactly how `briefingTrigger` works — the hook outputs an instruction and Claude follows it.

**Default:** `XGH_SCHEDULER` defaults to `"off"` (opt-in), consistent with `XGH_BRIEFING="${XGH_BRIEFING:-off}"`. Set `XGH_SCHEDULER=on` in the shell environment or `CLAUDE.local.md` to enable.

### 1.2 CronCreate prompt format and job identification

CronCreate has no `label` field. Use the exact prompt text as the identifier:

- retrieve job: `prompt: "/xgh-retrieve"`
- analyze job: `prompt: "/xgh-analyze"`

`/xgh-schedule` identifies jobs by matching `prompt` exactly via CronList output. Do **not** prefix with `xgh:retrieve` or similar — that confuses Claude when the prompt fires.

### 1.3 CronCreate 3-day auto-expiry

CronCreate recurring jobs auto-expire after 3 days. For long-running sessions, jobs will silently stop. Mitigation:

- `/xgh-schedule` status output must include the job creation time (from CronList if available) so users can see age.
- If `/xgh-schedule` detects 0 active xgh jobs (CronList returns nothing matching `/xgh-retrieve` or `/xgh-analyze`), it offers: "No scheduler jobs found. Re-create them? [y/n]"
- The session-start hook's scheduler instruction is re-evaluated every session open, so jobs are always re-created on a fresh window.

### 1.4 Lifecycle

Cron jobs fire only within the session that created them. When Claude is closed, jobs stop. They are re-created automatically the next time a session opens (if `XGH_SCHEDULER=on`). Users should expect retrieve/analyze to pause when Claude is not open — this is intentional.

First retrieve cron fire may be delayed if the briefing skill is running at session start (CronCreate docs: jobs only fire when the REPL is idle). This is normal.

### 1.5 `/xgh-schedule` — interactive control panel

**New files:**
- `plugin/commands/schedule.md` — slash command definition
- `plugin/skills/schedule/schedule.md` — skill implementation

**Behaviour:**

| Invocation | Action |
|---|---|
| `/xgh-schedule` (no args) | CronList → show active xgh jobs, creation time, 3-day expiry warning if approaching |
| `/xgh-schedule pause retrieve` | CronDelete the retrieve job |
| `/xgh-schedule pause analyze` | CronDelete the analyze job |
| `/xgh-schedule resume retrieve` | Re-create retrieve cron (`*/5 * * * *`, prompt `/xgh-retrieve`) |
| `/xgh-schedule resume analyze` | Re-create analyze cron (`*/30 * * * *`, prompt `/xgh-analyze`) |
| `/xgh-schedule run retrieve` | Fire `/xgh-retrieve` immediately (not via cron) |
| `/xgh-schedule run analyze` | Fire `/xgh-analyze` immediately |
| `/xgh-schedule off` | CronDelete both xgh jobs |
| `/xgh-schedule prefs` | Show all stored skill mode preferences from `~/.xgh/prefs.json` |
| `/xgh-schedule prefs reset <skill>` | Delete `skill_mode.<skill>` from `~/.xgh/prefs.json` and re-prompt next invocation |

The skill is interactive (foreground), short, always runs in the main session.

### 1.6 Remove OS-level scheduler

- Delete `scripts/ingest-schedule.sh`.
- Delete `scripts/schedulers/` directory (launchd plist templates).
- Remove the `ingest-schedule` component from `techpack.yaml`.
- Remove the scheduler install block from `install.sh` (lines ~1087–1145).
- **Migration for existing installs:** Before deleting `ingest-schedule.sh`, the new `install.sh` must call `bash "$HOME/.xgh/lib/ingest-schedule.sh" uninstall 2>/dev/null || true` to clean up any previously installed launchd agents. Run this before removing the script from the lib directory.
- Update `install.sh` output text: "Models run automatically as a daemon (launchd/systemd)" → "Retrieve and analyze run automatically each Claude session. Enable with XGH_SCHEDULER=on."
- Update `plugin/commands/retrieve.md` and `plugin/commands/analyze.md`: replace "Invoked automatically by the scheduler (launchd/cron)" with "Invoked automatically each session via CronCreate when XGH_SCHEDULER=on."

---

## 2. Background Agent Execution

### 2.1 Headless skills — always run in main session

Skills: `xgh:retrieve`, `xgh:analyze`, `xgh:briefing`

**Important design correction from original:** These skills are triggered by CronCreate, which fires prompts directly in the **main session**. There is no extra Agent dispatch layer for headless skills — they already run in their own turn (the cron turn). Wrapping them in a background Agent would add unnecessary latency and complexity.

Instead, update the headless skill markdown to:

1. Route all heavy output through `ctx_execute` / `ctx_batch_execute` (already specified in retrieve/analyze — reinforce this).
2. Write results to disk (`~/.xgh/inbox/` for retrieve; lossless-claude for analyze) rather than printing them to session context.
3. End the turn with a one-line summary only: `"Retrieve complete: 3 new items stashed, 0 critical."` No raw tool output in context.

This pattern keeps the main session context clean without needing a sub-agent.

**MCP access note:** CronCreate fires prompts in the main session, so full MCP access (Slack, Jira, Figma, lossless-claude) is available. No sub-agent isolation concern.

Note: `plugin/skills/brief/` does not exist on disk — `brief-skill` in `techpack.yaml` is a stale reference. Out of scope here.

### 2.2 Interactive skills — preference-gated background Agent dispatch

Skills: `xgh:investigate`, `xgh:implement`, `xgh:index`, `xgh:track`, `xgh:collab`

These ARE the right candidates for Agent dispatch because they are user-initiated (not cron-fired) and can be genuinely parallelized.

Each skill's `.md` file gains a **Preamble** section. The preamble uses `python3` (universally available in xgh environments, already used by hooks) instead of `jq` to avoid a new dependency.

```markdown
## Preamble — Execution mode

1. **Read preference** — run this Bash command:
   ```bash
   python3 -c "
   import json, sys
   try:
     p = json.load(open('$HOME/.xgh/prefs.json'))
     v = p.get('skill_mode', {}).get('<skill_name>')
     print(json.dumps(v) if v else '')
   except: print('')
   "
   ```
   If output is non-empty JSON, use `mode` and `autonomy` from it and skip to **Dispatch**.

2. **If not set** — ask the user (one question at a time):
   - "Run **<skill>** in background (returns summary when done) or interactive? [b/i, default: i]"
   - If "b": "Check in with a question before starting, or fire-and-forget? [c/f, default: c]"

3. **Write preference** — run this Bash command:
   ```bash
   python3 -c "
   import json, os
   path = os.path.expanduser('~/.xgh/prefs.json')
   os.makedirs(os.path.dirname(path), exist_ok=True)
   try: p = json.load(open(path))
   except: p = {}
   p.setdefault('skill_mode', {})['<skill_name>'] = <entry_json>
   json.dump(p, open(path, 'w'), indent=2)
   "
   ```
   Where `<entry_json>` is `{"mode":"interactive"}` for interactive, or `{"mode":"background","autonomy":"check-in"|"fire-and-forget"}` for background.

4. **Flag overrides** (text-matched in the invocation string, do not update prefs.json):
   - invocation contains `--bg` → treat as background
   - invocation contains `--interactive` or `--fg` → treat as interactive
   - invocation contains `--checkin` → use check-in autonomy (background only)
   - invocation contains `--auto` → use fire-and-forget autonomy (background only)
   - invocation contains `--reset` → delete `skill_mode.<skill_name>` from prefs.json, re-prompt

   Note: these are not parsed flags — Claude matches them as substrings in the raw invocation text.

## Dispatch

**Interactive mode:** proceed with normal skill flow (existing instructions below).

**Background / check-in mode:**
  - Ask any essential clarifying questions in the main session first (max 2 questions).
  - Collect full context: user's request verbatim, relevant files, current branch, recent git log.
  - Dispatch via Agent tool (`run_in_background: true`) with a fully self-contained prompt.
  - Report back: "Agent started for <skill> — I'll post results when done."
  - When agent completes, post a ≤5-bullet summary to main session.

**Background / fire-and-forget mode:**
  - Collect context automatically (read files, git log — no questions).
  - Dispatch via Agent tool (`run_in_background: true`).
  - Report back: "Agent started for <skill> — I'll post results when done."
  - When agent completes, post a ≤5-bullet summary to main session.
```

### 2.3 `~/.xgh/prefs.json` schema

```json
{
  "skill_mode": {
    "investigate": { "mode": "background", "autonomy": "check-in" },
    "implement":   { "mode": "interactive" },
    "index":       { "mode": "background", "autonomy": "fire-and-forget" },
    "track":       { "mode": "interactive" },
    "collab":      { "mode": "interactive" }
  }
}
```

- `mode`: `"background"` | `"interactive"`
- `autonomy` (only when `mode = "background"`): `"check-in"` | `"fire-and-forget"`

---

## 3. Files Changed

| File | Change |
|---|---|
| `plugin/hooks/session-start.sh` | Add `XGH_SCHEDULER` env var handling; inject `schedulerTrigger` flag + CronCreate instructions into `additionalContext` |
| `plugin/commands/schedule.md` | New — `/xgh-schedule` command |
| `plugin/skills/schedule/schedule.md` | New — schedule control panel skill |
| `plugin/skills/retrieve/retrieve.md` | Reinforce ctx_execute pattern; update output to one-line summary; remove "invoked by launchd/cron" |
| `plugin/skills/analyze/analyze.md` | Same as retrieve |
| `plugin/skills/briefing/briefing.md` | Same output discipline (one-line summary to main session) |
| `plugin/skills/investigate/investigate.md` | Add preamble preference check (Python3 variant) |
| `plugin/skills/implement/implement.md` | Add preamble preference check |
| `plugin/skills/index/index.md` | Add preamble preference check |
| `plugin/skills/track/track.md` | Add preamble preference check |
| `plugin/skills/collab/collab.md` | Add preamble preference check |
| `plugin/commands/retrieve.md` | Update scheduler reference text |
| `plugin/commands/analyze.md` | Update scheduler reference text |
| `install.sh` | Run `ingest-schedule.sh uninstall` (migration), remove scheduler install block, update output text |
| `scripts/ingest-schedule.sh` | Delete |
| `scripts/schedulers/com.xgh.retriever.plist` | Delete |
| `scripts/schedulers/com.xgh.analyzer.plist` | Delete |
| `scripts/schedulers/com.xgh.models.plist` | **Keep or verify separately** — this manages vllm-mlx (embeddings server), not the retrieve/analyze pipeline. Do not delete without confirming that lossless-claude handles the model daemon independently. Out of scope for this feature. |
| `techpack.yaml` | Remove `ingest-schedule` component |
| `tests/test-hooks.sh` | Update expected JSON schema to include `schedulerTrigger` key |

---

## 4. Out of Scope

- `doctor`, `status`, `ask`, `curate`, `profile`, `calibrate`, `help`, `init`, `design` — short, synchronous, or UI-facing. No mode preference needed.
- Persisting cron job IDs across sessions — CronCreate is session-scoped; jobs are always re-created at session start.
- Cross-machine preference sync — `~/.xgh/prefs.json` is local only.
- `com.xgh.models.plist` / vllm-mlx daemon — separate concern, out of scope.
- `brief-skill` / `plugin/skills/brief/` stale reference cleanup — separate cleanup task.
