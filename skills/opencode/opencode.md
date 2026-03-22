---
name: xgh:opencode
description: "This skill should be used when the user asks to \"dispatch to opencode\", \"run opencode\", \"opencode exec\", \"opencode review\", \"use opencode for\", \"send to opencode\", or wants to delegate implementation or code review tasks to OpenCode CLI agent. Supports worktree-isolated parallel dispatch and same-directory sequential dispatch."
---

> **Context-mode:** This skill primarily runs Bash commands. Use Bash directly for git
> and opencode commands (short output). Use `Read` to review opencode output files.

## Preamble — Execution mode

Before starting, check whether the user has a saved execution mode preference for this skill.

**Step P1 — Read preference:**
```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.xgh/prefs.json')
try:
    p = json.load(open(path))
    v = p.get('skill_mode', {}).get('opencode')
    print(json.dumps(v) if v else '')
except: print('')
"
```
If output is non-empty JSON, extract `mode` and `autonomy` (if present) and skip to **Dispatch** below.

**Step P2 — If not set, ask the user (one question at a time):**
- "Run **opencode dispatch** in background (returns summary when done) or interactive? [b/i, default: i]"
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
p['skill_mode']['opencode'] = entry
json.dump(p, open(path, 'w'), indent=2)
" "<mode>" "<autonomy>"
```

**Step P4 — Flag overrides** (check the raw invocation text; do not update prefs.json):
- contains `--bg` -> use background mode
- contains `--interactive` or `--fg` -> use interactive mode
- contains `--checkin` -> use check-in autonomy
- contains `--auto` -> use fire-and-forget autonomy
- contains `--reset` -> run `python3 -c "import json,os; p=json.load(open(os.path.expanduser('~/.xgh/prefs.json'))); p.get('skill_mode',{}).pop('opencode',None); json.dump(p,open(os.path.expanduser('~/.xgh/prefs.json'),'w'),indent=2)"` then re-prompt

**Dispatch:**

**Interactive mode** -> proceed with the skill normally (continue to the rest of this file).

**Background / check-in mode:**
1. Ask at most 2 essential clarifying questions in the main session.
2. Collect context: user's request verbatim, dispatch type, model preference, current branch.
3. Dispatch via Agent tool with `run_in_background: true`. Prompt must be fully self-contained.
4. Reply: "OpenCode dispatch running in background -- I'll post results when done."
5. When agent completes: post results summary to main session.

**Background / fire-and-forget mode:**
1. Collect context automatically (no questions).
2. Dispatch via Agent tool with `run_in_background: true`.
3. Reply: "OpenCode dispatch running in background -- I'll post results when done."
4. When agent completes: post results summary.

---

# xgh:opencode -- OpenCode CLI Dispatch

Dispatch implementation tasks or code reviews to OpenCode CLI as a parallel or sequential agent. OpenCode runs non-interactively via `opencode run "<prompt>"`, optionally in an isolated git worktree for safe parallel work alongside Claude Code.

## Prerequisites

Check OpenCode CLI availability:

```bash
command -v opencode >/dev/null 2>&1 && opencode --version || echo "NOT_INSTALLED"
```

If `NOT_INSTALLED`, print: "OpenCode CLI not found. Install with: `npm i -g opencode-ai`" and stop.

**Note:** OpenCode natively reads `.claude/skills/` and `~/.claude/CLAUDE.md` — xgh skills are available automatically. Verify: `opencode --help | grep -i skill`. Run `/xgh-seed` before dispatch to inject project context into `.opencode/skills/xgh/`.

## Input Parsing

Parse the user's request to determine dispatch parameters. Only extract what the user explicitly provides — all other flags stay at OpenCode CLI defaults.

**Spawning management flags** (always injected by the skill):

| Flag | Purpose |
|------|---------|
| `cd <dir>` | Working directory (worktree path or current dir) — set via shell cd, not a CLI flag |
| `> <output>` | Capture output via redirect (not a CLI flag — shell redirect) |

Note: No `--full-auto` needed — non-interactive mode (passing a prompt to `opencode run`) auto-approves all permissions.
Note: No `-s read-only` for review — enforced via prompt engineering ("Do NOT modify any files").

**User-controlled parameters** (only injected if the user explicitly provides them):

| Parameter | Default | User flag |
|-----------|---------|-----------|
| `type` | `exec` | first arg: `exec` or `review` |
| `isolation` | `worktree` (exec), `same-dir` (review) | `--worktree`, `--same-dir` |
| `prompt` | — | remaining text after type |
| `model` | CLI default | `--model <provider>/<name>` (e.g. `--model anthropic/claude-opus-4-6`) |

**Passthrough flags** (forwarded verbatim to OpenCode CLI if the user includes them):

| Flag | What it controls |
|------|-----------------|
| `--model <provider>/<name>` | Model override (e.g., `anthropic/claude-opus-4-6`, `openai/gpt-5.4`) |

Any unrecognized flags are forwarded to `opencode run` as-is.

---

## Step 1: Setup Workspace

### Worktree mode

Create an isolated git worktree for OpenCode to work in:

```bash
SLUG=$(echo "<prompt-summary>" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | cut -c1-30)
TIMESTAMP=$(date +%s)
BRANCH="opencode/${SLUG}-${TIMESTAMP}"
WORKTREE=".worktrees/opencode-${TIMESTAMP}"
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

Build the command with spawning management flags plus any user-specified passthrough flags. Output is captured via shell redirect:

```bash
OUTPUT_FILE="/tmp/opencode-exec-${TIMESTAMP}.md"
# Worktree mode:
cd "$WORK_DIR" && opencode run "$PROMPT" $PASSTHROUGH_FLAGS > "$OUTPUT_FILE" 2>&1
# Same-dir mode: same but cd to repo root
```

- **Worktree mode:** Run via Bash with `run_in_background: true`. Claude Code is free to continue other work while OpenCode runs.
- **Same-dir mode:** Run synchronously. Claude Code waits for completion.

### Review dispatch

```bash
OUTPUT_FILE="/tmp/opencode-review-${TIMESTAMP}.md"
cd "$WORK_DIR" && opencode run "Code review: $PROMPT. Analyze the code and provide detailed feedback. Do NOT modify any files." $PASSTHROUGH_FLAGS > "$OUTPUT_FILE" 2>&1
```

Note: Review is enforced via prompt engineering — OpenCode has no `-s read-only` equivalent.

---

## Step 3: Collect Results

Read the output file with the Read tool (output is typically short enough for direct context).

For worktree mode, also summarize what OpenCode changed:

```bash
git -C "$WORK_DIR" log --oneline "$BRANCH" --not main
git -C "$WORK_DIR" diff --stat main..."$BRANCH"
```

Present a structured summary to the user:

```
## OpenCode Dispatch Results

| Field | Value |
|-------|-------|
| Type | exec / review |
| Model | <model> |
| Isolation | worktree ($BRANCH) / same-dir |
| Files changed | N |
| Duration | Xs |

### OpenCode Output
<summary or full content of output file>

### Changes (worktree mode)
<git log + diff stat>
```

If the output file is large (>200 lines), summarize the key points rather than including the full content.

---

## Step 4: Integration (worktree mode only)

Ask the user how to integrate OpenCode's changes:

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
lcm_store("OpenCode dispatch: <type> | model: <model> | isolation: <mode> | <outcome summary>", ["session", "opencode"])
```

---

## Model Selection

| Model | When to use |
|-------|-------------|
| CLI default | Latest model configured in OpenCode |
| `--model anthropic/claude-opus-4-6` | Anthropic Claude Opus via OpenCode |
| `--model anthropic/claude-sonnet-4-6` | Faster, good balance |
| `--model openai/gpt-5.4` | OpenAI GPT-5.4 via OpenCode |

## Sandbox Policy

| Mode | Approach | Rationale |
|------|----------|-----------|
| Worktree exec | non-interactive auto-approves | Isolated directory, safe for auto-approve |
| Same-dir exec | non-interactive auto-approves | User explicitly chose same-dir |
| Review | prompt-engineered "Do NOT modify files" | No native read-only sandbox flag |

## Anti-Patterns

- **Vague prompts.** OpenCode works best with focused, specific tasks. "Fix all the bugs" will produce poor results. "Add unit tests for the TokenBucket.consume() method in src/lib/token-bucket.ts" will succeed.
- **Same-dir during parallel work.** Do not use same-dir mode while Claude Code is also editing files. Use worktree mode instead.
- **Skipping results review.** Always read and verify OpenCode output before merging. OpenCode may introduce unexpected changes.
- **Large monolithic dispatches.** Split large tasks into focused subtasks, dispatching each to a separate OpenCode invocation.
- **Review without prompt constraint.** Always include 'Do NOT modify any files' in review prompts — OpenCode has no native read-only sandbox flag.
