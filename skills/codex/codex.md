---
name: xgh:codex
description: "This skill should be used when the user asks to \"dispatch to codex\", \"run codex\", \"codex exec\", \"codex review\", \"use codex for\", \"send to codex\", or wants to delegate implementation or code review tasks to OpenAI's Codex CLI agent. Supports worktree-isolated parallel dispatch and same-directory sequential dispatch (--add-dir)."
---

> **Context-mode:** This skill primarily runs Bash commands. Use Bash directly for git
> and codex commands (short output). Use `Read` to review codex output files.

## How to dispatch

**ALWAYS dispatch via the `xgh:codex-driver` agent** using the Agent tool with `subagent_type: "xgh:codex-driver"`.

The `xgh:codex-driver` agent handles:
- Flag detection and command construction
- Model fallback
- Sandbox config
- Output parsing
- Retry logic

> **WARNING: Do NOT run `codex` CLI commands directly via Bash.**
> Invoking `codex exec` or `codex review` directly bypasses flag detection, model fallback, sandbox config, output parsing, and retry logic. All dispatch MUST go through the `xgh:codex-driver` agent.

See [Step 2: Dispatch](#step-2-dispatch) for the agent prompt format.

---

## Preamble — Execution mode

Follow the shared execution mode protocol in `skills/_shared/references/execution-mode-preamble.md`. Apply it to this skill's command name.

- `<SKILL_NAME>` = `codex`
- `<SKILL_LABEL>` = `Codex dispatch`

---

# xgh:codex -- Codex CLI Dispatch

Dispatch implementation tasks or code reviews to OpenAI's Codex CLI as a parallel or sequential agent. Codex runs non-interactively via `codex exec` or `codex review`, optionally in an isolated git worktree for safe parallel work alongside Claude Code.

> **Shared workflow:** Steps 1, 3, 4, and 5 follow `skills/_shared/references/dispatch-template.md`.
> Use `<CLI>` = `codex`, `<CLI_LABEL>` = `Codex`, `<cli>` = `codex`, `<tag>` = `codex`.

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
| `-C <dir>` | Working directory (worktree path or current dir) — exec only |
| `-o <file>` | Capture final output to file for results collection — exec only |

**User-controlled parameters** (only injected if the user explicitly provides them):

| Parameter | Codex default | User flag |
|-----------|---------------|-----------|
| `type` | `exec` | first arg: `exec` or `review` |
| `isolation` | `worktree` (exec), `same-dir` (review) | `--worktree`, `--add-dir <dir>` |
| `prompt` | — | remaining text after type |
| `review_target` | `--base main` | `--uncommitted`, `--commit <sha>`, `--base <branch>` |
| `effort` | CLI default | `--effort <level>` or `--thinking <level>` (translated to `-c 'model_reasoning_effort="..."'`) |
| `session` | stateless (`--ephemeral`) | `--session` — opt-in stateful mode; captures UUID for resumption |
| `session_id` | — | `--session-id <UUID>` — resume a specific prior session |

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

Follow `skills/_shared/references/dispatch-template.md` Step 1. Use `<CLI>` = `codex`.

**Same-dir mode:** Set `WORK_DIR=$(pwd)`. No worktree is created. For exec, pass `--add-dir $(pwd)` in the Codex invocation so the sandbox grants write access to the repo directory. Note: `--add-dir` is a Codex sandbox flag, not the isolation selector — same-dir mode is chosen when the user does not want worktree isolation (e.g. for reviews, or explicit `--add-dir` choice).

---

## Step 2: Dispatch

Use the **Agent tool** with `subagent_type: "xgh:codex-driver"` to dispatch. The codex-driver agent handles flag detection, command construction, execution, and returns a structured result. Do NOT run Codex via Bash directly — route through the agent.

Construct the agent prompt from the parsed parameters:

**Exec:**
```
Dispatch type: exec
Working directory: <WORK_DIR>
Isolation: worktree | same-dir
Prompt: <full prompt text including verification footer>
Model: <if specified>
Effort: <if specified>
Passthrough flags: <any user-provided flags>
```

**Review:**
```
Dispatch type: review
Working directory: <WORK_DIR>
Review target: --base <branch> | --uncommitted | --commit <sha>
Effort: <if specified>
Passthrough flags: <any user-provided flags>
```

- **Worktree exec:** Set `run_in_background: true` on the Agent call. Confirm to the user that Codex is running.
- **Same-dir exec / review:** Run synchronously (no `run_in_background`). Wait for the result.

---

## Step 3: Collect Results

Follow `skills/_shared/references/dispatch-template.md` Step 3. Use `<CLI_LABEL>` = `Codex`.

The codex-driver agent returns a structured result block — surface it directly. The `git log` / `diff stat` commands are run by the agent and included in its result.

---

## Step 4: Integration (worktree mode only)

Follow `skills/_shared/references/dispatch-template.md` Step 4.

---

## Step 5: Curate (if lossless-claude available)

Follow `skills/_shared/references/dispatch-template.md` Step 5. Use `<CLI_LABEL>` = `Codex`, `<cli>` = `codex`.

**Write observation to model profiles** (always, regardless of lossless-claude):

After the dispatch completes, append one observation to `.xgh/model-profiles.yaml`. Create the file if it doesn't exist.

```yaml
# Append to .xgh/model-profiles.yaml
- agent: codex
  model: <the -m flag value, or "default" if none was passed>
  effort: <the --effort value, or "default" if none was passed>
  archetype: <set by router if dispatched via /xgh-dispatch, otherwise "unknown">
  accepted: <true if worktree merged or user continued; false if re-dispatched or discarded>
  ts: <ISO 8601 timestamp>
```

Write this observation using a python one-liner (stdlib only — no external dependencies):

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
    'agent': 'codex',
    'model': '<MODEL>',
    'effort': '<EFFORT>',
    'archetype': '<ARCHETYPE>',
    'accepted': True,  # or False based on outcome
    'ts': datetime.datetime.now(datetime.timezone.utc).isoformat()
})
json.dump(data, open(path, 'w'), indent=2)
"
```

Replace `<MODEL>`, `<EFFORT>`, `<ARCHETYPE>` with the actual values from the dispatch. Determine `accepted` from:
- Worktree merged → `true`
- User continued to next task → `true`
- User re-dispatched same task → `false`
- User discarded worktree → `false`

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
| Review | `-c 'sandbox_permissions=["disk-full-read-access"]'` | Read-only access via config (no file modifications) |

## Session Mode

By default every dispatch is **stateless** (`--ephemeral`): fresh context, no history, parallel-safe.

`--session` opts into **stateful mode**: Codex persists the session and returns a UUID. Use `--session-id <UUID>` on follow-up dispatches to resume exactly where it left off (`codex resume`).

### When to use `--session`

Only when the task is **inherently iterative** and Codex genuinely needs to carry state forward:

- Exploratory debugging where each step narrows the root cause and the next step depends on prior findings
- Multi-turn investigation where Codex needs to remember what it already ruled out
- A deliberate "pairing session" where you'll prompt Codex several times in sequence

### When NOT to use `--session` (the common case)

- Any task with a complete written spec — stateless is always preferable
- Running multiple tasks in parallel — sessions serialize, worktrees do not
- After a failed attempt — session history will carry the wrong assumptions forward
- If you're not sure — default stateless, no regrets

### Risks — read before enabling

| Risk | What happens |
|------|-------------|
| **Context contamination** | Prior failed attempts accumulate. Codex doubles down on wrong paths instead of reconsidering. |
| **No parallelism** | One session = one process. Parallel worktree dispatch is blocked. |
| **Non-determinism** | Same prompt → different result depending on what Codex remembers. Hard to reproduce. |
| **Stale state** | Hours-old session describes a repo state that no longer exists. Codex acts on outdated context. |
| **Opaque history** | Claude cannot see what Codex "remembers". Unexpected behavior is hard to diagnose. |

**The rule:** if you can write a self-contained prompt Codex can execute from scratch, use stateless. Session mode is for the rare case where accumulated context is the feature, not a liability.

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

See shared anti-patterns in `skills/_shared/references/dispatch-template.md`.

Codex-specific additions:
- **Vague prompts.** "Fix all the bugs" produces poor results. "Fix `src/auth.ts:42` — null check missing before `.userId` access" succeeds.
- **No verification step.** Always include a test command in the prompt. Codex won't self-verify unless told to.
- **No scope constraints.** Codex will touch whatever seems related. If you don't say "modify only X", it will modify Y and Z too.
