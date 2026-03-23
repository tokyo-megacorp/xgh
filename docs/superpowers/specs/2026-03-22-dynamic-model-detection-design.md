# Dynamic Model Detection & Routing System — Design Spec

**Date:** 2026-03-22
**Status:** Approved
**Related:** `.xgh/plans/2026-03-20-dynamic-provider-generation.md`

## Overview

Extend xgh's dynamic provider generation to include **model discovery and routing**. When users say "review with GLM 4.7", the system detects the model mention, looks up the CLI format from dynamically-generated mappings, and routes to the correct provider with the correct flags.

**Problem solved:** Currently, model mappings are hardcoded in `skills/_shared/references/model-mapping.md`. When CLIs add/remove models, skills must be manually updated.

**Solution:** Probe CLI `--help` output, generate per-agent `models.yaml`, and route dispatches through dynamically-discovered mappings.

## Architecture

### Components

1. **`/xgh-coding-agents` command** — New skill that probes CLIs and generates `models.yaml`
2. **Per-agent model storage** — `~/.xgh/user_providers/<agent>/models.yaml`
3. **Model detection in dispatch skills** — Pattern matching + lookup from generated mappings
4. **Lazy initialization** — Skills probe if `models.yaml` is missing/stale

### Data Flow

```
User: "review with GLM 4.7"
         ↓
Dispatch skill detects "GLM 4.7"
         ↓
Looks up ~/.xgh/user_providers/opencode/models.yaml
         ↓
Finds: GLM 4.7 → zai-coding-plan/glm-4.7
         ↓
Routes to opencode-driver with --model flag
```

### Separation of Concerns

| Component | Reads | Writes |
|-----------|-------|--------|
| `/xgh-coding-agents` | CLI `--help` output | `models.yaml` |
| Dispatch skills | `models.yaml` | — |
| Driver agents | — | CLI commands |

Dispatch skills are **readers** of model data. `/xgh-coding-agents` is the single writer.

## Component Details

### 1. `/xgh-coding-agents` Skill

**Location:** `skills/coding-agents/coding-agents.md`

**Commands:**
```bash
/xgh-coding-agents                    # List all agents + their models
/xgh-coding-agents opencode           # Show OpenCode details
/xgh-coding-agents --refresh          # Re-probe all agents
/xgh-coding-agents opencode --refresh # Re-probe just OpenCode
```

**Probing strategy:**

| CLI | Discovery method | Command |
|-----|------------------|---------|
| OpenCode | `--help` for `--model` format | `opencode --help` |
| Codex | `--help` for model list | `codex exec --help` |
| Gemini | `--help` for model flags | `gemini --help` |

**Output schema:**
```yaml
# ~/.xgh/user_providers/opencode/models.yaml
agent: opencode
cli_binary: opencode
last_probed: 2026-03-22T20:00:00Z
models:
  - friendly: GLM 4.7
    cli_format: zai-coding-plan/glm-4.7
    aliases: [glm, glm-4.7]
  - friendly: Claude Opus
    cli_format: anthropic/claude-opus-4-6
    aliases: [opus, claude-opus]
```

### 2. Model Detection in Dispatch Skills

**Patterns to scan for:**
- "with <model>" → "review with GLM 4.7"
- "using <model>" → "implement using GPT-5.4"
- "via <model>" → "code review via Claude Opus"

**Detection logic:**
1. Parse user input for patterns
2. Extract candidate model name
3. Read agent's `models.yaml`
4. Match against `friendly` or `aliases` fields
5. Return `cli_format` for routing

### 3. Lazy Initialization

**On dispatch, before routing:**
```bash
MODELS_FILE="$HOME/.xgh/user_providers/opencode/models.yaml"

# Probe if missing or stale (>7 days)
if [ ! -f "$MODELS_FILE" ] || [ $(find "$MODELS_FILE" -mtime +7) ]; then
  /xgh-coding-agents opencode --refresh
fi
```

### 4. Error Handling

| Scenario | Behavior |
|----------|----------|
| Model not found | AskUserQuestion: "GLM 7 not found. Available: GLM-5, GPT-5.4, Claude Opus... [Pick one/Use default]" |
| CLI not installed | Log warning, skip that agent, continue with others |
| models.yaml corrupt | Re-probe CLI, log error, fallback to hardcoded defaults |
| Probe fails | Log error, mark agent as "probe-failed", don't retry until next manual refresh |

## Testing Strategy

### 1. Unit Tests

| Component | Test |
|-----------|------|
| `/xgh-coding-agents` probe | Mock CLI `--help` output, verify generated YAML |
| Model detection | Test patterns against various inputs |
| Lookup logic | Mock models.yaml, verify correct matches |
| Lazy init | Test missing/stale file triggers |

### 2. Integration Tests

**Test probe → dispatch flow:**
```bash
# Setup: Mock opencode --help output
# Run: /xgh-coding-agents opencode --refresh
# Verify: models.yaml created with correct entries

# Run: /xgh-opencode "review with GLM 4.7"
# Verify: Routes to opencode-driver with correct --model flag
```

**Test file:** `tests/test-coding-agents.sh`

### 3. Manual Verification

```bash
/xgh-coding-agents --refresh        # Probe all CLIs
/xgh-coding-agents opencode         # Show OpenCode models
/xgh-opencode "fix bug with GLM 4.7"   # Verify routing
```

## File Structure

| Action | Path | Responsibility |
|--------|------|---------------|
| Create | `skills/coding-agents/coding-agents.md` | CLI probing skill |
| Create | `commands/coding-agents.md` | Command entry point |
| Modify | `skills/opencode/opencode.md` | Add model detection patterns |
| Modify | `skills/codex/codex.md` | Add model detection patterns |
| Modify | `skills/gemini/gemini.md` | Add model detection patterns |
| Create | `skills/_shared/references/model-detection.md` | Shared detection logic |
| Delete | `skills/_shared/references/model-mapping.md` | Replaced by dynamic generation |
| Create | `tests/test-coding-agents.sh` | Tests |
| Modify | `config/agents.yaml` | Add coding-agents driver agent |
| Modify | `AGENTS.md` | Document new command |

## Implementation Notes

- **Backward compatibility:** If `models.yaml` is missing, fall back to hardcoded defaults
- **Stale data:** 7-day threshold for refresh is configurable via env var
- **User customization:** Users can manually edit `models.yaml` to add aliases
- **Probe idempotency:** Re-probing preserves user customizations
