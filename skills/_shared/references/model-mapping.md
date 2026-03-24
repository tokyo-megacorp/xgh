# Model Mapping Reference

Canonical mappings from friendly model names to CLI-specific model formats.

## Purpose

When users mention models in natural language ("use GLM 4.7", "with GPT-5.4", "via Claude Opus"), dispatch skills need to:
1. Detect the model mention
2. Map it to the CLI's expected format
3. Pass it as a parameter to the driver agent

## Mappings by CLI

### OpenCode (`--model provider/name`)

| Friendly Name | OpenCode Format |
|--------------|-----------------|
| GLM 5, GLM-5 | `zai-coding-plan/glm-5` |
| GLM 5 Turbo, GLM-5-Turbo | `zai-coding-plan/glm-5-turbo` |
| GLM 4.7, GLM-4.7 | `zai-coding-plan/glm-4.7` |
| Claude Opus 4.6, Opus, claude-opus | `anthropic/claude-opus-4-6` |
| Claude Sonnet 4.6, Sonnet, claude-sonnet | `anthropic/claude-sonnet-4-6` |
| GPT 5.4, GPT-5.4 | `openai/gpt-5.4` |
| GPT 5.4 Mini, GPT-5.4-mini | `openai/gpt-5.4-mini` |

### Codex (`-m <model>`)

| Friendly Name | Codex Format |
|--------------|--------------|
| GPT 5.4, GPT-5.4 | `gpt-5.4` (default) |
| GPT 5.4 Mini, GPT-5.4-mini | `gpt-5.4-mini` |
| GPT 5.3 Codex | `gpt-5.3-codex` |
| GPT 5.1 Codex Max | `gpt-5.1-codex-max` |
| GPT 5.1 Codex Mini | `gpt-5.1-codex-mini` |
| o3, o3-preview | `o3` |

### Gemini (via `--model` flag)

| Friendly Name | Gemini Format |
|--------------|---------------|
| Gemini 2.5 Pro | `gemini-2.5-pro` |
| Gemini 2.5 Flash | `gemini-2.5-flash` |
| Gemini 2.0 Flash | `gemini-2.0-flash` |

## Detection Patterns

Model mentions typically appear as:
- "with <model>" → "with GLM 4.7"
- "using <model>" → "using GPT-5.4"
- "via <model>" → "via Claude Opus"
- "<model> please" → "GLM 4.7 please"
- "use <model>" → "use GPT-5.4"

## Routing Logic

When a model is detected:

1. **Determine CLI from model name:**
   - GLM models → OpenCode (Z.AI Coding Plan)
   - GPT models → Codex or OpenCode (user preference)
   - Claude models → OpenCode or Codex (user preference)
   - Gemini models → Gemini CLI

2. **Map to CLI format:**
   - Use the table above to translate friendly name to CLI flag

3. **Route to appropriate skill:**
   - Pass the mapped model format to the driver agent

## Example Transformations

| User Input | Detected Model | CLI | Model Flag |
|-----------|---------------|-----|------------|
| "review this with GLM 4.7" | GLM 4.7 | OpenCode | `--model zai-coding-plan/glm-4.7` |
| "implement using GPT-5.4" | GPT-5.4 | Codex | `-m gpt-5.4` |
| "code review via Claude Opus" | Claude Opus | OpenCode | `--model anthropic/claude-opus-4-6` |
| "dispatch to gemini: fix the bug" | (default) | Gemini | (none, use default) |
