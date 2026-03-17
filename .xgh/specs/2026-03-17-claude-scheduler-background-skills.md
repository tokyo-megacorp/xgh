# Claude-Internal Scheduler & Background Skill Execution

> **For agentic workers:** Use superpowers:subagent-driven-development to implement this plan.

**Goal:** Replace OS-level cron/launchd with Claude's built-in CronCreate for session-scoped scheduling, and give each xgh skill the ability to run as a background Agent with per-skill execution mode preferences.

**Architecture:** Session-start hook auto-creates CronCreate jobs for retrieve/analyze. A new `/xgh-schedule` command is the interactive control panel. Headless skills always dispatch as background Agents. Interactive skills check `~/.xgh/prefs.json` on invocation and prompt the user once to capture mode + autonomy preferences.

**Tech Stack:** Bash (hook, prefs helpers), Markdown (skill instructions), JSON (`~/.xgh/prefs.json`), Claude Code CronCreate/CronDelete/CronList tools, Agent tool.

---

## 1. Session-scoped Scheduler

### 1.1 Auto-start via session-start hook

`plugin/hooks/session-start.sh` already supports `XGH_BRIEFING=1` to auto-trigger the briefing skill. Add parallel support for `XGH_SCHEDULER` (default: `1`):

- If `XGH_SCHEDULER` is `"on"`, inject a `scheduler_trigger` key into the JSON payload output by the hook. Uses `"on"`/`"off"` strings, consistent with the existing `XGH_BRIEFING` convention.
- **Default is `"off"`** — consistent with `XGH_BRIEFING="${XGH_BRIEFING:-off}"`. Users opt in by setting `XGH_SCHEDULER=on` in their environment or `CLAUDE.local.md`. This is intentional: auto-scheduling on every session without consent would be disruptive.
- The session-start hook instructions detect `scheduler_trigger` and call CronCreate twice:
  - retrieve: `cron: "*/5 * * * *"`, `prompt: "xgh:retrieve /xgh-retrieve"`, `recurring: true`
  - analyze: `cron: "*/30 * * * *"`, `prompt: "xgh:analyze /xgh-analyze"`, `recurring: true`
- Because CronCreate does not support a dedicated `label` field, jobs are identified by matching the `prompt` field via CronList (prompts prefixed with `xgh:retrieve` / `xgh:analyze`).
- Set `XGH_SCHEDULER=off` in the environment to disable for a session.
- **Lifecycle:** Cron jobs fire only within the session that created them. When the Claude window is closed, jobs stop. They are re-created automatically on the next session start. Users should expect retrieve/analyze to pause when Claude is not open — this is intentional (session-scoped by design).

### 1.2 `/xgh-schedule` — interactive control panel

**New files:**
- `plugin/commands/schedule.md` — slash command definition
- `plugin/skills/schedule/schedule.md` — skill implementation

**Behaviour:**

| Invocation | Action |
|---|---|
| `/xgh-schedule` (no args) | List all active xgh cron jobs via CronList, show next fire time and last result |
| `/xgh-schedule pause retrieve` | CronDelete the retrieve job |
| `/xgh-schedule pause analyze` | CronDelete the analyze job |
| `/xgh-schedule resume retrieve` | Re-create retrieve cron (`*/5 * * * *`) |
| `/xgh-schedule resume analyze` | Re-create analyze cron (`*/30 * * * *`) |
| `/xgh-schedule run retrieve` | Fire `/xgh-retrieve` immediately (one-off, not via cron) |
| `/xgh-schedule run analyze` | Fire `/xgh-analyze` immediately |
| `/xgh-schedule off` | CronDelete all xgh cron jobs for this session |
| `/xgh-schedule prefs reset <skill>` | Delete `skill_mode.<skill>` from `~/.xgh/prefs.json` and re-prompt on next invocation |
| `/xgh-schedule prefs` | Show all stored skill mode preferences |

The skill is interactive (foreground), short, and always runs in the main session — it's the management interface, not a task itself.

### 1.3 Remove OS-level scheduler

- Delete `scripts/ingest-schedule.sh`.
- Delete `scripts/schedulers/` directory (launchd plist templates).
- Remove the `ingest-schedule` component from `techpack.yaml`.
- Remove the scheduler install block from `install.sh` (the section that copies plist templates and calls `ingest-schedule.sh install`).
- Update `install.sh` output text: replace "Models run automatically as a daemon (launchd/systemd)" with a note about session-scoped scheduling.
- Update `plugin/commands/retrieve.md` and `plugin/commands/analyze.md`: replace "Invoked automatically by the scheduler (launchd/cron)" with "Invoked automatically each session via CronCreate".

---

## 2. Background Agent Execution

### 2.1 Headless skills — always background

Skills: `xgh:retrieve`, `xgh:analyze`, `xgh:briefing`

Note: `plugin/skills/brief/` does not exist on disk — `brief-skill` in `techpack.yaml` is a stale reference. No action needed here; that is a separate cleanup task.

These never interact with the user. Their skill `.md` files are updated to dispatch via the `Agent` tool and return only a summary:

```
## Execution

Dispatch this skill as a background Agent:
- subagent_type: general-purpose
- run_in_background: true
- prompt: [full self-contained task description with all needed context]

Wait for the agent result, then return a one-paragraph summary to the main session.
Do NOT stream raw tool output into the main session context.
```

No preference check, no prompt — always background.

### 2.2 Interactive skills — preference-gated

Skills: `xgh:investigate`, `xgh:implement`, `xgh:index`, `xgh:track`, `xgh:collab`

Each skill's `.md` file gains a **Preamble** section (before any existing content) that runs the preference check. The preamble instructs Claude to use concrete tool calls — `Bash` for reading/writing `~/.xgh/prefs.json` via `jq`.

```markdown
## Preamble — Execution mode

1. **Read preference** using Bash:
   ```bash
   jq -r '.skill_mode.<skill_name> // empty' ~/.xgh/prefs.json 2>/dev/null
   ```
   If output is non-empty, parse `mode` and `autonomy` and skip to "Dispatch".

2. **If not set** — ask the user:
   - "Run **<skill>** in background (returns summary) or interactive? [b/i, default: i]"
   - If "b": "Check in before starting or fire-and-forget? [c/f, default: c]"

3. **Write preference** using Bash:
   ```bash
   mkdir -p ~/.xgh
   prefs=$(cat ~/.xgh/prefs.json 2>/dev/null || echo '{}')
   # When mode is "interactive", omit autonomy key entirely:
   if [ "<mode>" = "interactive" ]; then
     entry='{"mode":"interactive"}'
   else
     entry='{"mode":"<mode>","autonomy":"<autonomy>"}'
   fi
   echo "$prefs" | jq --argjson e "$entry" '.skill_mode.<skill_name> = $e' \
     > ~/.xgh/prefs.json
   ```

4. **Flag overrides** (per-invocation, do not update prefs.json):
   - `--bg` → background mode
   - `--interactive` / `--fg` → interactive mode
   - `--checkin` → check-in autonomy (background only)
   - `--auto` → fire-and-forget autonomy (background only)
   - `--reset` → delete `skill_mode.<skill_name>` from prefs.json and re-prompt

## Dispatch

**Interactive mode:** proceed with normal skill flow (existing instructions below).

**Background / check-in mode:**
  - Ask any essential clarifying questions in the main session first (max 2).
  - Collect full context: task description, relevant files, current branch, recent git log.
  - Dispatch via Agent tool (run_in_background: true) with a self-contained prompt.
  - Wait for result, post summary to main session.

**Background / fire-and-forget mode:**
  - Collect context automatically (no questions).
  - Dispatch via Agent tool (run_in_background: true).
  - Wait for result, post summary to main session.
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
- `autonomy` (only meaningful when `mode = "background"`): `"check-in"` | `"fire-and-forget"`

---

## 3. Files Changed

| File | Change |
|---|---|
| `plugin/hooks/session-start.sh` | Add `XGH_SCHEDULER` env var support, inject `scheduler_trigger` |
| `plugin/hooks/session-start.sh` (inline prompt) | On `scheduler_trigger`, call CronCreate for retrieve + analyze |
| `plugin/commands/schedule.md` | New — `/xgh-schedule` command |
| `plugin/skills/schedule/schedule.md` | New — schedule control panel skill |
| `plugin/skills/retrieve/retrieve.md` | Add background Agent dispatch pattern |
| `plugin/skills/analyze/analyze.md` | Add background Agent dispatch pattern |
| `plugin/skills/briefing/briefing.md` | Add background Agent dispatch pattern |
| `plugin/skills/brief/brief.md` | Does not exist on disk — skip. `brief-skill` in `techpack.yaml` is a stale reference; out of scope here. |
| `plugin/skills/investigate/investigate.md` | Add preamble preference check |
| `plugin/skills/implement/implement.md` | Add preamble preference check |
| `plugin/skills/index/index.md` | Add preamble preference check |
| `plugin/skills/track/track.md` | Add preamble preference check |
| `plugin/skills/collab/collab.md` | Add preamble preference check |
| `plugin/commands/retrieve.md` | Update scheduler reference text |
| `plugin/commands/analyze.md` | Update scheduler reference text |
| `install.sh` | Remove scheduler install block, update output text |
| `scripts/ingest-schedule.sh` | Delete |
| `scripts/schedulers/com.xgh.retriever.plist` | Delete (replaced by CronCreate) |
| `scripts/schedulers/com.xgh.analyzer.plist` | Delete (replaced by CronCreate) |
| `scripts/schedulers/com.xgh.models.plist` | Delete — this is the local model daemon plist (vllm-mlx/Ollama). The model server is now managed exclusively by `lossless-claude install` (its own daemon setup). Confirm at implementation time that no install.sh step still references this plist. |
| `techpack.yaml` | Remove `ingest-schedule` component |

---

## 4. Out of Scope

- `doctor`, `status`, `ask`, `curate`, `profile`, `calibrate`, `help`, `init`, `design` — these are short, synchronous, or UI-facing. No mode preference needed.
- Persisting cron job IDs across sessions — CronCreate is session-scoped by design; jobs are always re-created at session start.
- Cross-machine preference sync — `~/.xgh/prefs.json` is local only.
