---
name: xgh:glm
description: "This skill should be used when the user asks to \"dispatch to glm\", \"run glm\", \"glm exec\", \"glm review\", \"use glm for\", \"send to glm\", or wants to delegate implementation or code review tasks to Z.AI's GLM models via OpenCode CLI. Supports worktree-isolated parallel dispatch and same-directory sequential dispatch."
---

> **Context-mode:** This skill primarily runs Bash commands. Use Bash directly for git
> and opencode commands (short output). Use `Read` to review opencode output files.

## Preamble — Execution mode

Follow the shared execution mode protocol in `skills/_shared/references/execution-mode-preamble.md`. Apply it to this skill's command name.

- `<SKILL_NAME>` = `glm`
- `<SKILL_LABEL>` = `GLM dispatch`

---

# xgh:glm -- GLM Model Dispatch via OpenCode

Dispatch implementation tasks or code reviews to Z.AI's GLM models through OpenCode CLI. GLM runs non-interactively via `opencode run "<prompt>"` with `--model zai-coding-plan/glm-*`, optionally in an isolated git worktree for safe parallel work alongside Claude Code.

> This is a **convenience wrapper** around `xgh:opencode` that pre-configures GLM models. For advanced usage, use `/xgh-opencode` directly.

## Prerequisites

Check OpenCode CLI availability and z.ai configuration:

```bash
command -v opencode >/dev/null 2>&1 && opencode --version || echo "NOT_INSTALLED"
```

If `NOT_INSTALLED`, print: "OpenCode CLI not found. Install with: `npm i -g opencode-ai`" and stop.

Check z.ai coding plan configuration:

```bash
opencode auth list | grep -i "zai" || echo "ZAI_NOT_CONFIGURED"
```

If `ZAI_NOT_CONFIGURED`, print: "Z.AI Coding Plan not configured. Run: `opencode auth login` and select Z.AI Coding Plan" and stop.

## Input Parsing

Parse the user's request to determine dispatch parameters. Only extract what the user explicitly provides — all other flags stay at defaults.

**Spawning management flags** (always injected by the skill):

| Flag | Purpose |
|------|---------|
| `--model zai-coding-plan/<model>` | GLM model selection (injected based on user preference) |
| `cd <dir>` | Working directory (worktree path or current dir) — set via shell cd |
| `> <output>` | Capture output via redirect (shell redirect) |

**User-controlled parameters** (only injected if the user explicitly provides them):

| Parameter | Default | User flag |
|-----------|---------|-----------|
| `type` | `exec` | first arg: `exec` or `review` |
| `isolation` | `worktree` (exec), `same-dir` (review) | `--worktree`, `--same-dir` |
| `prompt` | — | remaining text after type |
| `model` | `glm-4.7` | `--model <name>` (e.g., `--model glm-5`, `--model glm-4.7`) |
| `effort` | CLI default | `--effort <level>` (maps to model selection) |

**Effort level to model mapping:**

| User says | Resolves to |
|-----------|-------------|
| `--effort low` / `--effort medium` | `zai-coding-plan/glm-4.7` |
| `--effort high` / `--effort max` | `zai-coding-plan/glm-5` |
| `--effort turbo` | `zai-coding-plan/glm-5-turbo` |
| `--model glm-4.7` | `zai-coding-plan/glm-4.7` |
| `--model glm-5` | `zai-coding-plan/glm-5` |
| `--model glm-5-turbo` | `zai-coding-plan/glm-5-turbo` |

**Passthrough flags** (forwarded verbatim to OpenCode CLI):

| Flag | What it controls |
|------|-----------------|
| `--attach <url>` | Attach to running OpenCode server (performance) |
| `--format json` | Output as JSON events |
| `--title <title>` | Session title |

---

## Step 1: Setup Workspace

Follow `skills/_shared/references/dispatch-template.md` Step 1. Use `<CLI>` = `opencode`, `<CLI_LABEL>` = `GLM`.

Same-dir fallback flag: `--same-dir`.

---

## Step 2: Dispatch

### Build command

Map user's model choice to full OpenCode model path, then dispatch:

```bash
# Model mapping (default: glm-4.7)
MODEL_MAP=(
    ["glm-4.7"]="zai-coding-plan/glm-4.7"
    ["glm-5"]="zai-coding-plan/glm-5"
    ["glm-5-turbo"]="zai-coding-plan/glm-5-turbo"
)

# Resolve model
MODEL="${MODEL_MAP[$USER_MODEL]:-zai-coding-plan/glm-4.7}"

OUTPUT_FILE="/tmp/glm-exec-${TIMESTAMP}.md"
cd "$WORK_DIR" && opencode run --model "$MODEL" "$PROMPT" $PASSTHROUGH_FLAGS > "$OUTPUT_FILE" 2>&1
```

- **Worktree mode:** Run via Bash with `run_in_background: true`. Claude Code is free to continue other work while GLM runs.
- **Same-dir mode:** Run synchronously. Claude Code waits for completion.

### Review dispatch

```bash
OUTPUT_FILE="/tmp/glm-review-${TIMESTAMP}.md"
cd "$WORK_DIR" && opencode run --model "$MODEL" "Code review: $PROMPT. Analyze the code and provide detailed feedback. Do NOT modify any files." $PASSTHROUGH_FLAGS > "$OUTPUT_FILE" 2>&1
```

---

## Step 3: Collect Results

Follow `skills/_shared/references/dispatch-template.md` Step 3. Use `<CLI_LABEL>` = `GLM`.

---

## Step 4: Integration (worktree mode only)

Follow `skills/_shared/references/dispatch-template.md` Step 4.

---

## Step 5: Curate (if memory backend available — see `_shared/references/memory-backend.md`)

Follow `skills/_shared/references/dispatch-template.md` Step 5. Use `<CLI_LABEL>` = `GLM`, `<cli>` = `opencode`.

---

## Model Selection

| Model | When to use |
|-------|-------------|
| `glm-4.7` (default) | Stable, reliable GLM model |
| `glm-5` | Latest frontier GLM model |
| `glm-5-turbo` | Faster variant of GLM-5 |

## Sandbox Policy

| Mode | Approach | Rationale |
|------|----------|-----------|
| Worktree exec | non-interactive auto-approves | Isolated directory, safe for auto-approve |
| Same-dir exec | non-interactive auto-approves | User explicitly chose same-dir |
| Review | prompt-engineered "Do NOT modify files" | No native read-only sandbox flag |

## Anti-Patterns

See shared anti-patterns in `skills/_shared/references/dispatch-template.md`.

GLM-specific additions:
- **Vague prompts.** GLM works best with focused, specific tasks. "Add unit tests for the TokenBucket.consume() method in src/lib/token-bucket.ts" will succeed where "Fix all the bugs" will not.
- **Review without prompt constraint.** Always include 'Do NOT modify any files' in review prompts — no native read-only sandbox flag.
- **Using z.ai API directly.** Always dispatch through OpenCode CLI to ensure coding plan quota applies correctly.
