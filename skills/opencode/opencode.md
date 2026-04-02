---
name: xgh:opencode
description: "This skill should be used when the user asks to \"dispatch to opencode\", \"run opencode\", \"opencode exec\", \"opencode review\", \"use opencode for\", \"send to opencode\", or wants to delegate implementation or code review tasks to OpenCode CLI agent. Supports worktree-isolated parallel dispatch and same-directory sequential dispatch."
---

> **Context-mode:** This skill primarily runs Bash commands. Use Bash directly for git
> and opencode commands (short output). Use `Read` to review opencode output files.

## Preamble — Execution mode

Follow the shared execution mode protocol in `skills/_shared/references/execution-mode-preamble.md`. Apply it to this skill's command name.

- `<SKILL_NAME>` = `opencode`
- `<SKILL_LABEL>` = `OpenCode dispatch`

---

# xgh:opencode -- OpenCode CLI Dispatch

Dispatch implementation tasks or code reviews to OpenCode CLI as a parallel or sequential agent. OpenCode runs non-interactively via `opencode run "<prompt>"`, optionally in an isolated git worktree for safe parallel work alongside Claude Code.

> **Shared workflow:** Steps 1, 3, 4, and 5 follow `skills/_shared/references/dispatch-template.md`.
> Use `<CLI>` = `opencode`, `<CLI_LABEL>` = `OpenCode`, `<cli>` = `opencode`, `<tag>` = `opencode`.

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

Follow `skills/_shared/references/dispatch-template.md` Step 1. Use `<CLI>` = `opencode`.

Same-dir fallback flag: `--same-dir`.

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

Follow `skills/_shared/references/dispatch-template.md` Step 3. Use `<CLI_LABEL>` = `OpenCode`.

---

## Step 4: Integration (worktree mode only)

Follow `skills/_shared/references/dispatch-template.md` Step 4.

---

## Step 5: Curate (if memory backend available — see `_shared/references/memory-backend.md`)

Follow `skills/_shared/references/dispatch-template.md` Step 5. Use `<CLI_LABEL>` = `OpenCode`, `<cli>` = `opencode`.

**Write observation to model profiles** (always, regardless of MAGI):

After the dispatch completes, append one observation to `.xgh/model-profiles.yaml`. Create the file if it doesn't exist.

```yaml
# Append to .xgh/model-profiles.yaml
- agent: opencode
  model: <the --model flag value, or "default" if none was passed>
  effort: default
  archetype: <set by router if dispatched via /xgh-dispatch, otherwise "unknown">
  accepted: <true if worktree merged or user continued; false if re-dispatched or discarded>
  ts: <ISO 8601 timestamp>
```

Note: OpenCode has no effort flag. Always record `effort: default`.

Write using the same python one-liner pattern (stdlib only), with `'agent': 'opencode'` and `'effort': 'default'`:

```bash
python3 -c "
import json, os, datetime
path = '.xgh/model-profiles.yaml'
os.makedirs(os.path.dirname(path), exist_ok=True)
try:
    data = json.load(open(path))
except (FileNotFoundError, json.JSONDecodeError):
    data = {'observations': []}
data.setdefault('observations', [])
data['observations'].append({
    'agent': 'opencode',
    'model': '<MODEL>',
    'effort': 'default',
    'archetype': '<ARCHETYPE>',
    'accepted': True,  # or False based on outcome
    'ts': datetime.datetime.now(datetime.timezone.utc).isoformat()
})
json.dump(data, open(path, 'w'), indent=2)
"
```

Replace `<MODEL>`, `<ARCHETYPE>` with the actual values from the dispatch. Determine `accepted` from:
- Worktree merged → `true`
- User continued to next task → `true`
- User re-dispatched same task → `false`
- User discarded worktree → `false`

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

See shared anti-patterns in `skills/_shared/references/dispatch-template.md`.

OpenCode-specific additions:
- **Vague prompts.** OpenCode works best with focused, specific tasks. "Add unit tests for the TokenBucket.consume() method in src/lib/token-bucket.ts" will succeed where "Fix all the bugs" will not.
- **Review without prompt constraint.** Always include 'Do NOT modify any files' in review prompts — OpenCode has no native read-only sandbox flag.
