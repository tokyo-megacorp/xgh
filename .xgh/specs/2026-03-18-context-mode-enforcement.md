# Context-Mode Enforcement for xgh

**Date:** 2026-03-18
**Status:** Draft (rev 2 — post spec review)
**Problem:** Context-mode goes unused despite advisory hooks, wasting tokens and money.

## Background

Context-mode provides tools (`ctx_execute_file`, `ctx_batch_execute`, `ctx_execute`) that keep
raw output in a sandbox, returning only printed summaries to the context window. Even a single
call can save 40% of context. However, in practice, agents routinely bypass these tools:

- Read is used for analysis instead of `ctx_execute_file`
- Bash is used for multi-command research instead of `ctx_batch_execute`
- Context-mode's PreToolUse hook fires advisory "tips" that are easily rationalized away

Root causes:
1. **Advisory hooks lack teeth** — "tip" framing is optional-feeling
2. **Zero context-mode awareness in skills** — superpowers and xgh skills never mention how to read files efficiently
3. **No session-level feedback loop** — nothing notices "5 Reads, 0 ctx calls" and escalates

## Prerequisites

**Installer hook copy path bug:** The installer copies hooks from `${PACK_DIR}/hooks/` but
the actual hook scripts live at `${PACK_DIR}/plugin/hooks/`. This causes the `if [ -f "$src" ]`
check to fail, creating empty placeholder hooks instead. The implementation plan must fix this
path before adding new hooks to the copy loop.

## Solution: Four-Layer Defense in Depth

Each layer strengthens the previous. Implementation order matches layer number.

### Layer 1: Foundation — Shared Reference Doc + Session-Start Priming

**New directory:** `plugin/references/`

**New file:** `plugin/references/context-mode-routing.md`

Single source of truth for context-mode routing rules. Contains:

- **Routing table:**

| Action | Tool | When |
|--------|------|------|
| Understand / analyze a file | `ctx_execute_file(path)` | Always, unless Edit follows within 1-2 tool calls |
| Read a file to Edit it | `Read` | Only when the next action is Edit on the same file |
| Run multiple commands / searches | `ctx_batch_execute(commands, queries)` | Any multi-command research |
| Run builds, tests, log processing | `ctx_execute(language, code)` | Output expected >20 lines |
| Quick git/mkdir/rm | `Bash` | Output expected <20 lines |

- **The "next action test":** If your next action is NOT an Edit on the same file, use
  `ctx_execute_file`.
- **Phase-specific guidance:**
  - Investigation/debugging: `ctx_execute_file` for all file reads, `ctx_batch_execute` for
    searches. Switch to `Read` only in implementation phase when editing.
  - Implementation: `Read` for files about to be Edited. `ctx_execute` for builds/tests.
- **Examples of correct and incorrect patterns** (drawn from real session mistakes).

**Session-start changes:**

1. Add to the `decision_table` list in `plugin/hooks/session-start.sh`:
   ```python
   "For file analysis: use ctx_execute_file, not Read. Read is only for files about to be Edited."
   ```

2. Add context-mode availability check:
   ```python
   # Check if context-mode MCP is available by looking for its plugin cache
   ctx_mode_available = Path.home().joinpath(
       ".claude/plugins/cache/context-mode"
   ).exists()
   ```
   Emit `"ctxModeAvailable": true/false` in the output. When false, suppress context-mode
   guidance in the decision table and do not initialize the state file.

This primes every session before any skill loads or tool fires.

### Layer 2: Teaching — Skill Preambles

**Inline preamble template** (carried by every xgh skill, ~4 lines):

```markdown
> **Context-mode:** Use `ctx_execute_file` for analysis reads; `Read` only for files you will
> Edit within 1-2 tool calls. Use `ctx_batch_execute` for multi-command research. Full routing
> rules: `plugin/references/context-mode-routing.md`
```

**Scope:** All xgh skills. The preamble is brief enough to not add noise to light skills
(doctor, schedule) while providing essential routing guidance to heavy skills (investigate,
implement, deep-retrieve).

**Heavy skills** (investigate, implement, deep-retrieve, retrieve, analyze) additionally
reference the full doc for phase-specific guidance in their own context-mode section.

**Skills to update (23 total):**
- `plugin/skills/investigate/investigate.md`
- `plugin/skills/implement/implement.md`
- `plugin/skills/deep-retrieve/deep-retrieve.md`
- `plugin/skills/retrieve/retrieve.md`
- `plugin/skills/analyze/analyze.md`
- `plugin/skills/briefing/briefing.md`
- `plugin/skills/doctor/doctor.md`
- `plugin/skills/init/init.md`
- `plugin/skills/track/track.md`
- `plugin/skills/index/index.md`
- `plugin/skills/profile/profile.md`
- `plugin/skills/schedule/schedule.md`
- `plugin/skills/calibrate/calibrate.md`
- `plugin/skills/collab/collab.md`
- `plugin/skills/design/design.md`
- `plugin/skills/ask/ask.md`
- `plugin/skills/curate/curate.md`
- `plugin/skills/command-center/command-center.md`
- `plugin/skills/knowledge-handoff/knowledge-handoff.md`
- `plugin/skills/mcp-setup/mcp-setup.md`
- `plugin/skills/pr-context-bridge/pr-context-bridge.md`
- `plugin/skills/todo-killer/todo-killer.md`
- `plugin/skills/team/` (all sub-skills: cross-team-pollinator, onboarding-accelerator, subagent-pair-programming)

### Layer 3: Enforcement — PreToolUse Hook with Escalating Warnings

**State file:** `/tmp/xgh-ctx-health-{hash}.json`

Where `{hash}` is derived from the worktree root:
```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HASH="$(echo "$PROJECT_ROOT" | shasum | cut -c1-8)"
STATE_FILE="/tmp/xgh-ctx-health-${HASH}.json"
```

This is worktree-safe — each worktree gets its own state file. `/tmp/` is cleaned up by the OS.

**State schema:**
```json
{
  "reads": 0,
  "edits": 0,
  "ctx_calls": 0,
  "files_read": []
}
```

**Session-start initialization:** The session-start hook resets the state file at the start of
every session (only when context-mode is available).

```python
import hashlib, subprocess, json
project_root = subprocess.check_output(
    ["git", "rev-parse", "--show-toplevel"],
    stderr=subprocess.DEVNULL
).decode().strip()
hash_val = hashlib.sha1(project_root.encode()).hexdigest()[:8]
state_path = f"/tmp/xgh-ctx-health-{hash_val}.json"
json.dump({"reads": 0, "edits": 0, "ctx_calls": 0, "files_read": []}, open(state_path, "w"))
```

**Missing state file resilience:** All hooks must handle the case where the state file is
missing mid-session (e.g., OS cleans `/tmp/`). If the file is missing, initialize a fresh
state rather than failing.

**Race condition on parallel tool calls:** With Claude Code's parallel tool calls, two hooks
could read/write the state file simultaneously, causing a lost increment. This is accepted
for an advisory system — the counters may occasionally be off by 1, which does not affect
the escalation tiers meaningfully.

**Hook implementation language:** All hooks use embedded Python (via `python3 -c "..."` or
heredoc) for consistency with the existing session-start and prompt-submit hooks.

**Hash consistency:** All hooks that compute the state file path must use the same algorithm:
`SHA-1 of the worktree root path, first 8 hex chars`. In Python: `hashlib.sha1(path.encode()).hexdigest()[:8]`.
All hash computations must use Python — do NOT use bash `echo | shasum` as echo adds a
trailing newline, producing a different hash.

**New hook: `plugin/hooks/pre-read.sh`** (PreToolUse on Read)

Output format (required for PreToolUse hooks):
```json
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "..."}}
```

On every Read call:
1. Compute state file path from worktree root hash
2. Read current state (or initialize fresh if missing), increment `reads`, append file path
   to `files_read`
3. Compute `unedited_reads = reads - edits`
4. If `ctx_calls >= 2`: suppress warnings (agent has demonstrated context-mode awareness)
5. Otherwise, emit `additionalContext` via `hookSpecificOutput` based on escalation tier:

| Unedited Reads | Level | Message |
|---|---|---|
| 0-2 | Tip | "Context-mode: use ctx_execute_file for analysis reads." |
| 3-4 | Recommendation | "You've read N files and edited M. Use ctx_execute_file for analysis. Unedited files: [list]" |
| 5+ | Strong warning | "N reads, M edits, 0 ctx calls. You are wasting context. Switch to ctx_execute_file NOW. See plugin/references/context-mode-routing.md" |

6. Write updated state back to file

**Known limitation — premature warnings on batch reads:** If an agent reads 5 files then edits
all 5, the 5th Read triggers a tier-3 warning even though all reads are edit-justified.
The post-edit hook resolves each file from the list as edits happen, so the counter self-corrects.
This brief false positive is accepted for an advisory system.

**New hook: `plugin/hooks/post-edit.sh`** (PostToolUse on Edit and Write)

On every Edit or Write call:
1. Read state file (or initialize fresh if missing)
2. Increment `edits`
3. Remove the edited/written file from `files_read` list (validates the preceding Read)
4. Write updated state back

Note: Write is tracked alongside Edit because a Read followed by Write (full rewrite) is
a valid read-then-modify pattern that should resolve the file from the unedited list.

**New hook: `plugin/hooks/post-ctx-call.sh`** (PostToolUse on context-mode tools)

On every context-mode tool call:
1. Read state file (or initialize fresh if missing)
2. Increment `ctx_calls`
3. Write updated state back

**Tracked context-mode tools** (all require PostToolUse matchers):
- `mcp__plugin_context-mode_context-mode__ctx_execute`
- `mcp__plugin_context-mode_context-mode__ctx_execute_file`
- `mcp__plugin_context-mode_context-mode__ctx_batch_execute`
- `mcp__plugin_context-mode_context-mode__ctx_search`
- `mcp__plugin_context-mode_context-mode__ctx_fetch_and_index`

### Layer 4: Feedback Loop — Session Health Nudge

**Integration point:** Existing `plugin/hooks/prompt-submit.sh` (UserPromptSubmit hook).

Output format (UserPromptSubmit):
```json
{"additionalContext": "..."}
```

On every user message, after existing intent detection logic:
1. Read state file (skip if missing — context-mode may not be installed)
2. If `ctx_calls >= 2`: skip nudge (agent is using context-mode)
3. If `unedited_reads >= 3` AND `ctx_calls < 2`: append nudge to `additionalContext`
4. Nudge text: "Session health: {reads} reads, {edits} edits, {ctx_calls} context-mode calls. Switch to
   ctx_execute_file for analysis reads."

**Design choices:**
- Fires per user message (low frequency, not noisy)
- Only triggers on a clear pattern (3+ unedited reads AND zero ctx calls)
- Suppressed once agent demonstrates awareness (ctx_calls >= 2)
- Appended to existing `additionalContext` output — no separate hook, single payload

## Hook Registration

The installer must register these hooks in the hooks settings. Use the existing
`hooks-settings.json` template pattern with `__HOOKS_DIR__` placeholder.

**PreToolUse hooks:**
```json
{
  "matcher": "Read",
  "hooks": [{"type": "command", "command": "bash __HOOKS_DIR__/xgh-pre-read.sh"}]
}
```

**PostToolUse hooks:**
```json
[
  {
    "matcher": "Edit",
    "hooks": [{"type": "command", "command": "bash __HOOKS_DIR__/xgh-post-edit.sh"}]
  },
  {
    "matcher": "Write",
    "hooks": [{"type": "command", "command": "bash __HOOKS_DIR__/xgh-post-edit.sh"}]
  },
  {
    "matcher": "mcp__plugin_context-mode_context-mode__ctx_execute",
    "hooks": [{"type": "command", "command": "bash __HOOKS_DIR__/xgh-post-ctx-call.sh"}]
  },
  {
    "matcher": "mcp__plugin_context-mode_context-mode__ctx_execute_file",
    "hooks": [{"type": "command", "command": "bash __HOOKS_DIR__/xgh-post-ctx-call.sh"}]
  },
  {
    "matcher": "mcp__plugin_context-mode_context-mode__ctx_batch_execute",
    "hooks": [{"type": "command", "command": "bash __HOOKS_DIR__/xgh-post-ctx-call.sh"}]
  },
  {
    "matcher": "mcp__plugin_context-mode_context-mode__ctx_search",
    "hooks": [{"type": "command", "command": "bash __HOOKS_DIR__/xgh-post-ctx-call.sh"}]
  },
  {
    "matcher": "mcp__plugin_context-mode_context-mode__ctx_fetch_and_index",
    "hooks": [{"type": "command", "command": "bash __HOOKS_DIR__/xgh-post-ctx-call.sh"}]
  }
]
```

## Installer Changes

The hook copy loop in `install.sh` must be updated:

1. **Fix the source path bug:** Change `${PACK_DIR}/hooks/${hook}.sh` to
   `${PACK_DIR}/plugin/hooks/${hook}.sh` (the actual location of hook scripts).

2. **Add new hooks to the copy loop:**
   ```bash
   for hook in session-start prompt-submit pre-read post-edit post-ctx-call; do
   ```

3. **Add new hook entries to `config/hooks-settings.json`** — add PreToolUse and PostToolUse
   sections to the existing file (which currently only has SessionStart and UserPromptSubmit).
   Use the `__HOOKS_DIR__` placeholder pattern already established in that file.

## File Inventory

| File | Action | Layer |
|------|--------|-------|
| `plugin/references/` | Create directory | 1 |
| `plugin/references/context-mode-routing.md` | Create | 1 |
| `plugin/hooks/session-start.sh` | Edit (decision table entry + ctx-mode check + state init) | 1, 3 |
| All 23 skill files listed above | Edit (add 4-line preamble) | 2 |
| `plugin/hooks/pre-read.sh` | Create (installed as `xgh-pre-read.sh`) | 3 |
| `plugin/hooks/post-edit.sh` | Create (installed as `xgh-post-edit.sh`) | 3 |
| `plugin/hooks/post-ctx-call.sh` | Create (installed as `xgh-post-ctx-call.sh`) | 3 |
| `config/hooks-settings.json` | Edit (add PreToolUse + PostToolUse entries) | 3 |
| `install.sh` | Edit (fix hook source path, add new hooks to copy loop) | 3 |
| `plugin/hooks/prompt-submit.sh` | Edit (add nudge logic) | 4 |

## Testing

- **Layer 1:** Verify session-start output includes the new decision table entry. Verify
  `ctxModeAvailable` is correct based on context-mode plugin presence.
- **Layer 2:** Spot-check 3-4 skills for preamble presence.
- **Layer 3:** Manual test:
  - Read 3 files without editing — verify escalation messages appear with correct format.
  - Edit a file — verify counter decrements and file removed from unedited list.
  - Use ctx_execute_file — verify ctx_calls increments.
  - After 2+ ctx calls — verify warnings are suppressed.
  - Delete state file mid-session — verify hooks re-initialize gracefully.
- **Layer 4:** Manual test: accumulate 3+ unedited reads with 0 ctx calls, send a message,
  verify nudge appears in additionalContext.
- **Worktree isolation:** Run two sessions in different worktrees, verify independent state files.
- **Context-mode absent:** Uninstall context-mode, verify hooks degrade gracefully (no errors,
  no misleading guidance).

## Risks

- **Hook performance:** Each Read/Edit adds a state file read/write + Python subprocess.
  `/tmp/` is fast, JSON is small, Python startup is ~30ms — acceptable for advisory hooks.
- **Context-mode not installed:** Session-start checks for context-mode availability and
  suppresses all context-mode guidance (decision table entry, state file init) when absent.
  PostToolUse matchers for ctx_* tools simply never fire. PreToolUse and nudge are gated on
  state file existence — if not initialized (ctx-mode absent), they silently skip.
- **Hook conflicts:** The installer uses deep-merge for hooks arrays. New hooks merge
  alongside context-mode's existing hooks without overwriting.
- **Race conditions:** Accepted for advisory system. Counters may be off by 1 on parallel
  tool calls. Does not affect escalation tiers meaningfully.
