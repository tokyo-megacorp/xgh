---
name: xgh:gemini
description: "This skill should be used when the user asks to \"dispatch to gemini\", \"run gemini\", \"use gemini for\", \"send to gemini\", \"gemini review\", or wants to delegate implementation or code review tasks to Google's Gemini CLI agent. Supports worktree-isolated parallel dispatch and same-directory sequential dispatch."
---

> **Context-mode:** This skill primarily runs Bash commands. Use Bash directly for git
> and gemini commands (short output). Use `Read` to review gemini output files.

## Preamble — Execution mode

Before starting, check whether the user has a saved execution mode preference for this skill.

**Step P1 — Read preference:**
```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.xgh/prefs.json')
try:
    p = json.load(open(path))
    v = p.get('skill_mode', {}).get('gemini')
    print(json.dumps(v) if v else '')
except: print('')
"
```
If output is non-empty JSON, extract `mode` and `autonomy` (if present) and skip to **Dispatch** below.

**Step P2 — If not set, ask the user (one question at a time):**
- "Run **gemini dispatch** in background (returns summary when done) or interactive? [b/i, default: i]"
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
p['skill_mode']['gemini'] = entry
json.dump(p, open(path, 'w'), indent=2)
" "<mode>" "<autonomy>"
```

**Step P4 — Flag overrides** (check the raw invocation text; do not update prefs.json):
- contains `--bg` -> use background mode
- contains `--interactive` or `--fg` -> use interactive mode
- contains `--checkin` -> use check-in autonomy
- contains `--auto` -> use fire-and-forget autonomy
- contains `--reset` -> run `python3 -c "import json,os; p=json.load(open(os.path.expanduser('~/.xgh/prefs.json'))); p.get('skill_mode',{}).pop('gemini',None); json.dump(p,open(os.path.expanduser('~/.xgh/prefs.json'),'w'),indent=2)"` then re-prompt

**Dispatch:**

**Interactive mode** -> proceed with the skill normally (continue to the rest of this file).

**Background / check-in mode:**
1. Ask at most 2 essential clarifying questions in the main session.
2. Collect context: user's request verbatim, dispatch type, model preference, current branch.
3. Dispatch via Agent tool with `run_in_background: true`. Prompt must be fully self-contained.
4. Reply: "Gemini dispatch running in background -- I'll post results when done."
5. When agent completes: post results summary to main session.

**Background / fire-and-forget mode:**
1. Collect context automatically (no questions).
2. Dispatch via Agent tool with `run_in_background: true`.
3. Reply: "Gemini dispatch running in background -- I'll post results when done."
4. When agent completes: post results summary.

---

# xgh:gemini -- Gemini CLI Dispatch

Dispatch implementation tasks or code reviews to Google's Gemini CLI as a parallel or sequential agent. Gemini runs non-interactively via `-p` (headless mode), optionally in an isolated git worktree for safe parallel work alongside Claude Code.

## Prerequisites

Check Gemini CLI availability:

```bash
command -v gemini >/dev/null 2>&1 && gemini --version || echo "NOT_INSTALLED"
```

If `NOT_INSTALLED`, print: "Gemini CLI not found. Install from: https://github.com/google-gemini/gemini-cli" and stop.

## Input Parsing

Parse the user's request to determine dispatch parameters. Only extract what the user explicitly provides -- all other flags stay at Gemini CLI defaults.

**Spawning management flags** (always injected by the skill):

| Flag | Purpose |
|------|---------|
| `-p "<prompt>"` | Non-interactive headless execution |
| `--yolo` | Auto-approve all actions (no confirmation prompts) |

**Note:** Gemini CLI has no `-C` (working directory) or `-o` (output file) flags. Working directory is set via `cd` before invocation. Output is captured via shell redirection.

**User-controlled parameters** (only injected if the user explicitly provides them):

| Parameter | Default | User flag |
|-----------|---------|-----------|
| `type` | `exec` | first arg: `exec` or `review` |
| `isolation` | `worktree` (exec), `same-dir` (review) | `--worktree`, `--same-dir` |
| `prompt` | -- | remaining text after type |
| `effort` | CLI default | `--effort <level>` or `--thinking <level>` (translated to Gemini thinking config) |

**Effort level translation** (accepts `--effort`, `--thinking` — maps to Gemini's model-dependent thinking config):

Gemini uses different thinking parameters depending on model generation:
- **Gemini 2.5 (Flash/Pro):** `thinking_budget` (integer tokens, 0-24576)
- **Gemini 3+:** `thinking_level` (enum: `MINIMAL`, `LOW`, `MEDIUM`, `HIGH`)

| User says | Gemini 3+ (`thinking_level`) | Gemini 2.5 (`thinking_budget`) |
|-----------|------------------------------|-------------------------------|
| `--effort low` / `--thinking low` | `LOW` | `1024` |
| `--effort medium` / `--thinking medium` | `MEDIUM` | `8192` |
| `--effort high` / `--thinking high` | `HIGH` | `16384` |
| `--effort max` / `--thinking max` | `HIGH` | `24576` |
| `--effort xhigh` / `--thinking xhigh` | `HIGH` | `24576` |
| `--effort minimal` / `--thinking minimal` | `MINIMAL` | `0` |

`--effort` and `--thinking` are aliases. `max` and `xhigh` (Anthropic/OpenAI jargon) both map to the maximum available. `minimal` maps to Gemini's native `MINIMAL` level. If the user passes a raw integer (e.g., `--thinking 16000`), treat it as a direct `thinking_budget` value for Gemini 2.5 models.

**Passthrough flags** (forwarded verbatim to Gemini CLI if the user includes them):

| Flag | What it controls |
|------|-----------------|
| `-m <model>` | Model override (e.g., `gemini-2.5-flash`) |
| `-s` | Enable sandbox mode |
| `--approval-mode <mode>` | Override approval (`default`, `auto_edit`, `yolo`, `plan`) |
| `--include-directories <dir>` | Additional workspace directories |
| `-e <ext>` | Limit to specific extensions |
| `--policy <file>` | Additional policy files |
| `-i <prompt>` | Execute prompt then continue interactively |
| `-o <format>` | Output format (`text`, `json`, `stream-json`) |
| `-r <session>` | Resume a previous session |

Any unrecognized flags are forwarded to `gemini` as-is.

---

## Step 1: Setup Workspace

### Worktree mode

Create an isolated git worktree for Gemini to work in:

```bash
SLUG=$(echo "<prompt-summary>" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | cut -c1-30)
TIMESTAMP=$(date +%s)
BRANCH="gemini/${SLUG}-${TIMESTAMP}"
WORKTREE=".worktrees/gemini-${TIMESTAMP}"
git worktree add "$WORKTREE" -b "$BRANCH"
```

Set `WORK_DIR="$WORKTREE"`.

If `git worktree add` fails (branch exists, dirty state), report the error and suggest `--same-dir` as fallback.

### Same-dir mode

Set `WORK_DIR` to the current working directory. No setup needed.

**Warning:** Do not use same-dir mode while Claude Code is also writing files. File conflicts will occur.

---

## Step 2: Dispatch

### Exec dispatch

Build the command with only spawning management flags plus any user-specified passthrough flags:

```bash
OUTPUT_FILE="/tmp/gemini-exec-${TIMESTAMP}.md"
CMD=(
    gemini
    -p "<prompt>"
    --yolo
    # User passthrough flags appended here (e.g., -m gemini-2.5-flash -s)
)
cd "$WORK_DIR" && "${CMD[@]}" > "$OUTPUT_FILE" 2>&1
```

- **Worktree mode:** Run via Bash with `run_in_background: true`. Claude Code is free to continue other work while Gemini runs.
- **Same-dir mode:** Run synchronously. Claude Code waits for completion.

### Review dispatch

For code review, use `--approval-mode plan` (read-only mode) instead of `--yolo`:

```bash
OUTPUT_FILE="/tmp/gemini-review-${TIMESTAMP}.md"
CMD=(
    gemini
    -p "<review prompt>"
    --approval-mode plan
    # User passthrough flags appended here
)
cd "$WORK_DIR" && "${CMD[@]}" > "$OUTPUT_FILE" 2>&1
```

Review prompt examples:
- "Review all changes on this branch vs main. Focus on correctness and test coverage."
- "Review the uncommitted changes. Check for security issues and error handling."

---

## Step 3: Collect Results

Read the output file with the Read tool (output is typically short enough for direct context).

For worktree mode, also summarize what Gemini changed:

```bash
git -C "$WORK_DIR" log --oneline "$BRANCH" --not main
git -C "$WORK_DIR" diff --stat main..."$BRANCH"
```

Present a structured summary to the user:

```
## Gemini Dispatch Results

| Field | Value |
|-------|-------|
| Type | exec / review |
| Model | (if specified via -m) |
| Isolation | worktree ($BRANCH) / same-dir |
| Files changed | N |
| Duration | Xs |

### Gemini Output
<summary or full content of output file>

### Changes (worktree mode)
<git log + diff stat>
```

If the output file is large (>200 lines), summarize the key points rather than including the full content.

---

## Step 4: Integration (worktree mode only)

Ask the user how to integrate Gemini's changes:

| Option | Command |
|--------|---------|
| **Merge** | `git merge $BRANCH` then cleanup |
| **Cherry-pick** | `git cherry-pick <commit-range>` then cleanup |
| **Keep for review** | Leave worktree at `$WORKTREE` for manual inspection |
| **Discard** | `git worktree remove "$WORKTREE" --force && git branch -D "$BRANCH"` |

Cleanup after merge or cherry-pick:
```bash
git worktree remove "$WORKTREE"
git branch -d "$BRANCH"
```

---

## Step 5: Curate (if lossless-claude available)

Store the dispatch outcome for future reference:

```
lcm_store("Gemini dispatch: <type> | model: <model> | isolation: <mode> | <outcome summary>", ["session", "gemini"])
```

---

## Approval Modes

Gemini CLI has four approval modes. The skill selects automatically based on dispatch type:

| Dispatch type | Approval mode | Behavior |
|--------------|---------------|----------|
| exec | `--yolo` | Auto-approve all actions (full write access) |
| review | `--approval-mode plan` | Read-only mode (no file modifications) |

The user can override via `--approval-mode <mode>`:

| Mode | Behavior |
|------|----------|
| `default` | Prompt for approval on each action |
| `auto_edit` | Auto-approve edit tools only |
| `yolo` | Auto-approve everything |
| `plan` | Read-only, no edits allowed |

## Anti-Patterns

- **Vague prompts.** Gemini works best with focused, specific tasks. "Fix all the bugs" will produce poor results. "Add unit tests for the TokenBucket.consume() method in src/lib/token-bucket.ts" will succeed.
- **Same-dir during parallel work.** Do not use same-dir mode while Claude Code is also editing files. Use worktree mode instead.
- **Skipping results review.** Always read and verify Gemini output before merging. Gemini may introduce unexpected changes.
- **Large monolithic dispatches.** Split large tasks into focused subtasks, dispatching each to a separate Gemini invocation. Mirrors the superpowers:dispatching-parallel-agents pattern.
