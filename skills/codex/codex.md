---
name: xgh:codex
description: "This skill should be used when the user asks to \"dispatch to codex\", \"run codex\", \"codex exec\", \"codex review\", \"use codex for\", \"send to codex\", or wants to delegate implementation or code review tasks to OpenAI's Codex CLI agent. Supports worktree-isolated parallel dispatch and same-directory sequential dispatch (--add-dir)."
trigger: "/xgh codex"
mcp_dependencies:
  required: []
  optional:
    - lossless-claude: "lossless-claude MCP — search past work, store outcomes"
---

> **Context-mode:** This skill primarily runs Bash commands. Use Bash directly for git
> and codex commands (short output). Use `Read` to review codex output files.

## Preamble — Execution mode

Before starting, check whether the user has a saved execution mode preference for this skill.

**Step P1 — Read preference:**
```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.xgh/prefs.json')
try:
    p = json.load(open(path))
    v = p.get('skill_mode', {}).get('codex')
    print(json.dumps(v) if v else '')
except: print('')
"
```
If output is non-empty JSON, extract `mode` and `autonomy` (if present) and skip to **Dispatch** below.

**Step P2 — If not set, ask the user (one question at a time):**
- "Run **codex dispatch** in background (returns summary when done) or interactive? [b/i, default: i]"
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
p['skill_mode']['codex'] = entry
json.dump(p, open(path, 'w'), indent=2)
" "<mode>" "<autonomy>"
```

**Step P4 — Flag overrides** (check the raw invocation text; do not update prefs.json):
- contains `--bg` -> use background mode
- contains `--interactive` or `--fg` -> use interactive mode
- contains `--checkin` -> use check-in autonomy
- contains `--auto` -> use fire-and-forget autonomy
- contains `--reset` -> run `python3 -c "import json,os; p=json.load(open(os.path.expanduser('~/.xgh/prefs.json'))); p.get('skill_mode',{}).pop('codex',None); json.dump(p,open(os.path.expanduser('~/.xgh/prefs.json'),'w'),indent=2)"` then re-prompt

**Dispatch:**

**Interactive mode** -> proceed with the skill normally (continue to the rest of this file).

**Background / check-in mode:**
1. Ask at most 2 essential clarifying questions in the main session.
2. Collect context: user's request verbatim, dispatch type, model preference, current branch.
3. Dispatch via Agent tool with `run_in_background: true`. Prompt must be fully self-contained.
4. Reply: "Codex dispatch running in background -- I'll post results when done."
5. When agent completes: post results summary to main session.

**Background / fire-and-forget mode:**
1. Collect context automatically (no questions).
2. Dispatch via Agent tool with `run_in_background: true`.
3. Reply: "Codex dispatch running in background -- I'll post results when done."
4. When agent completes: post results summary.

---

# xgh:codex -- Codex CLI Dispatch

Dispatch implementation tasks or code reviews to OpenAI's Codex CLI as a parallel or sequential agent. Codex runs non-interactively via `codex exec` or `codex review`, optionally in an isolated git worktree for safe parallel work alongside Claude Code.

## Prerequisites

Check Codex CLI availability:

```bash
command -v codex >/dev/null 2>&1 && codex --version || echo "NOT_INSTALLED"
```

If `NOT_INSTALLED`, print: "Codex CLI not found. Install with: `npm i -g @openai/codex`" and stop.

## Input Parsing

Parse the user's request to determine dispatch parameters. Only extract what the user explicitly provides — all other flags stay at Codex CLI defaults.

**Spawning management flags** (always injected by the skill):

| Flag | Purpose |
|------|---------|
| `--full-auto` | Non-interactive execution (auto-approve + workspace-write sandbox) — exec only |
| `-s read-only` | Read-only sandbox — review only |
| `-C <dir>` | Working directory (worktree path or current dir) |
| `-o <file>` | Capture final output to file for results collection |

**User-controlled parameters** (only injected if the user explicitly provides them):

| Parameter | Codex default | User flag |
|-----------|---------------|-----------|
| `type` | `exec` | first arg: `exec` or `review` |
| `isolation` | `worktree` (exec), `same-dir` (review) | `--worktree`, `--add-dir <dir>` |
| `prompt` | — | remaining text after type |
| `review_target` | `--base main` | `--uncommitted`, `--commit <sha>`, `--base <branch>` |
| `effort` | CLI default | `--effort <level>` or `--thinking <level>` (translated to `-c 'model_reasoning_effort="..."'`) |

**Effort level translation** (accepts `--effort`, `--thinking`, or raw `-c` — all resolve the same way):

| User says | Resolves to | OpenAI config |
|-----------|-------------|---------------|
| `--effort low` / `--thinking low` | low | `-c 'model_reasoning_effort="low"'` |
| `--effort medium` / `--thinking medium` | medium | `-c 'model_reasoning_effort="medium"'` |
| `--effort high` / `--thinking high` | high | `-c 'model_reasoning_effort="high"'` |
| `--effort max` / `--thinking max` | xhigh | `-c 'model_reasoning_effort="xhigh"'` |
| `--effort xhigh` / `--thinking xhigh` | xhigh | `-c 'model_reasoning_effort="xhigh"'` |

`--effort` and `--thinking` are aliases — both translate to `model_reasoning_effort`. The value `max` (Anthropic jargon) maps to `xhigh` (OpenAI jargon). All other values pass through as-is. If the user passes `-c 'model_reasoning_effort="..."'` directly, forward without translation.

**Passthrough flags** (forwarded verbatim to Codex CLI if the user includes them):

| Flag | What it controls |
|------|-----------------|
| `-m <model>` | Model override (e.g., `gpt-5.4-mini`, `gpt-5.1-codex-mini`) |
| `-s <policy>` | Sandbox override (`read-only`, `workspace-write`, `danger-full-access`) |
| `--search` | Enable live web search |
| `--add-dir <dir>` | Additional writable directories |
| `--ephemeral` | Skip session persistence |
| `-i <file>` | Attach image(s) to prompt |
| `-p <profile>` | Codex config profile from `~/.codex/config.toml` |
| `-c <key=value>` | Codex config override |

Any unrecognized flags are forwarded to `codex exec` / `codex review` as-is.

---

## Step 1: Setup Workspace

### Worktree mode

Create an isolated git worktree for Codex to work in:

```bash
SLUG=$(echo "<prompt-summary>" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | cut -c1-30)
TIMESTAMP=$(date +%s)
BRANCH="codex/${SLUG}-${TIMESTAMP}"
WORKTREE=".worktrees/codex-${TIMESTAMP}"
git worktree add "$WORKTREE" -b "$BRANCH"
```

Set `WORK_DIR="$WORKTREE"`.

If `git worktree add` fails (branch exists, dirty state), report the error and suggest `--add-dir <repo-path>` as fallback for same-directory dispatch.

### Same-dir mode

Set `WORK_DIR` to the current working directory. No worktree setup needed. Pass `--add-dir "$WORK_DIR"` to Codex so it has write access.

**Warning:** Do not use same-dir mode while Claude Code is also writing files. File conflicts will occur.

---

## Step 2: Dispatch

### Exec dispatch

Build the command with only spawning management flags plus any user-specified passthrough flags:

```bash
OUTPUT_FILE="/tmp/codex-exec-${TIMESTAMP}.md"
CMD=(
    codex exec "<prompt>"
    --full-auto
    -C "$WORK_DIR"
    -o "$OUTPUT_FILE"
    # Same-dir mode only: --add-dir "$WORK_DIR"
    # User passthrough flags appended here (e.g., -m gpt-5.4-mini --search)
)
"${CMD[@]}" 2>&1
```

- **Worktree mode:** Run via Bash with `run_in_background: true`. Claude Code is free to continue other work while Codex runs.
- **Same-dir mode:** Add `--add-dir "$WORK_DIR"` to give Codex write access. Run synchronously. Claude Code waits for completion.

### Review dispatch

```bash
OUTPUT_FILE="/tmp/codex-review-${TIMESTAMP}.md"
CMD=(
    codex review
    # Review target flag (e.g., --base main, --uncommitted, --commit <sha>)
    -s read-only
    -C "$WORK_DIR"
    # User passthrough flags appended here
)
"${CMD[@]}" > "$OUTPUT_FILE" 2>&1
```

Custom review instructions via prompt argument:
```bash
codex review --base main "Focus on security vulnerabilities and error handling"
```

---

## Step 3: Collect Results

Read the output file with the Read tool (output is typically short enough for direct context).

For worktree mode, also summarize what Codex changed:

```bash
git -C "$WORK_DIR" log --oneline "$BRANCH" --not main
git -C "$WORK_DIR" diff --stat main..."$BRANCH"
```

Present a structured summary to the user:

```
## Codex Dispatch Results

| Field | Value |
|-------|-------|
| Type | exec / review |
| Model | gpt-5.4 / gpt-5.4 / etc. |
| Isolation | worktree ($BRANCH) / same-dir (--add-dir) |
| Files changed | N |
| Duration | Xs |

### Codex Output
<summary or full content of output file>

### Changes (worktree mode)
<git log + diff stat>
```

If the output file is large (>200 lines), summarize the key points rather than including the full content.

---

## Step 4: Integration (worktree mode only)

Ask the user how to integrate Codex's changes:

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
lcm_store("Codex dispatch: <type> | model: <model> | isolation: <mode> | <outcome summary>", ["session", "codex"])
```

---

## Model Selection

| Model | When to use |
|-------|-------------|
| `gpt-5.4` (CLI default) | Latest frontier agentic coding model. Best for most tasks. |
| `gpt-5.4-mini` | Smaller frontier model. Faster, good balance of speed and capability. |
| `gpt-5.3-codex` | Codex-optimized frontier. Legacy codex lineage, still strong for coding. |
| `gpt-5.1-codex-max` | Deep and fast reasoning. Complex algorithm design, security-sensitive code. |
| `gpt-5.1-codex-mini` | Cheapest and fastest. Test generation, small refactors, lint fixes. |

## Sandbox Policy

| Mode | Sandbox | Rationale |
|------|---------|-----------|
| Worktree exec | `--full-auto` | Isolated directory, safe for auto-approve |
| Same-dir exec | `--full-auto --add-dir <dir>` | User explicitly chose same-dir |
| Review | `-s read-only` | Enforced read-only sandbox — no file modifications |

## Prompt Crafting

Codex runs to completion without mid-task steering. The quality of the prompt determines the quality of the result. **Before dispatching, verify the prompt passes all five checks:**

| Check | Bad (will fail or guess wrong) | Good (will succeed) |
|-------|-------------------------------|---------------------|
| **Specificity** | "Fix the frontmatter parser" | "Fix `scripts/gen-agents-md.sh:40` — `frontmatter()` silently swallows YAML errors; print `WARNING: <file>: <exception>` to stderr and continue" |
| **File scope** | "Update the tests" | "Modify only `tests/test-config.sh`. Do not touch any other files." |
| **Success criteria** | (none) | "After fixing, run: `bash tests/test-config.sh` — all must pass (currently 65/67)" |
| **Numbered tasks** | "Fix issues 1, 3, 7 and the brittle assertions" | "1. Fix X in `a.py:12`. 2. Fix Y in `b.yaml:5`. 3. Run tests. 4. Commit as `fix: ...`" |
| **Commit instruction** | (none) | "Commit all changes as: `fix: address review comments`" |

**Scope constraint template** — always include when touching multiple files:

```
Work in <dir>. Modify only: <file1>, <file2>. Do not touch any other files.
After changes, run: <test-command> — all must pass.
Commit as: '<message>'
```

**Clarification signals** — if any of these are true, do NOT dispatch yet. Clarify first:

- Task description is a single vague sentence with no file references
- No success criteria (how will Codex know it's done?)
- Scope is unbounded ("fix everything", "clean up the code")
- Task requires a decision mid-run ("pick the better approach")
- The outcome depends on something Codex can't read (Slack thread, verbal context, image)

## Anti-Patterns

- **Vague prompts.** "Fix all the bugs" produces poor results. "Fix `src/auth.ts:42` — null check missing before `.userId` access" succeeds.
- **No verification step.** Always include a test command in the prompt. Codex won't self-verify unless told to.
- **No scope constraints.** Codex will touch whatever seems related. If you don't say "modify only X", it will modify Y and Z too.
- **Same-dir during parallel work.** Do not use `--add-dir` while Claude Code is also editing files. Use worktree mode.
- **Skipping results review.** Always read and verify Codex output before merging.
- **Large monolithic dispatches.** Split into focused subtasks, one Codex invocation each.
