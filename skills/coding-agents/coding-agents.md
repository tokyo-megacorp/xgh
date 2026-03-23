---
name: xgh:coding-agents
description: "Use when the user asks to \"/xgh-coding-agents\", wants to see available coding agents (Codex, OpenCode, Gemini), probe CLI capabilities, or refresh model mappings."
---

# xgh:coding-agents — Coding Agent Management

List and manage AI coding CLI agents (Codex, OpenCode, Gemini) and their model capabilities.

## Usage

```bash
/xgh-coding-agents                    # List all agents + their models
/xgh-coding-agents opencode           # Show OpenCode details
/xgh-coding-agents --refresh          # Re-probe all agents
/xgh-coding-agents opencode --refresh # Re-probe just OpenCode
```

## Implementation

See [implementation plan](../../docs/superpowers/plans/2026-03-22-dynamic-model-detection.md).

## OpenCode Probing

**Discovery command:**
```bash
opencode --help
```

**Implementation note:** Phase 1 uses hardcoded model mappings with correct YAML structure. Future phases will parse `opencode --help` output for dynamic discovery.

**Models to detect:**
- GLM series: `zai-coding-plan/glm-5`, `zai-coding-plan/glm-5-turbo`, `zai-coding-plan/glm-4.7`
- Claude series: `anthropic/claude-opus-4-6`, `anthropic/claude-sonnet-4-6`
- OpenAI series: `openai/gpt-5.4`, `openai/gpt-5.4-mini`

**Probe function:**
```bash
probe_opencode() {
  local models_dir="$HOME/.xgh/user_providers/opencode"
  local output_file="$models_dir/models.yaml"

  mkdir -p "$models_dir"

  # Generate models.yaml
  cat > "$output_file" << YAML
agent: opencode
cli_binary: opencode
last_probed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
models:
  - friendly: GLM 5
    cli_format: zai-coding-plan/glm-5
    aliases: [glm-5, glm5]
  - friendly: GLM 5 Turbo
    cli_format: zai-coding-plan/glm-5-turbo
    aliases: [glm-5-turbo]
  - friendly: GLM 4.7
    cli_format: zai-coding-plan/glm-4.7
    aliases: [glm, glm-4.7, glm4.7]
  - friendly: Claude Opus 4.6
    cli_format: anthropic/claude-opus-4-6
    aliases: [opus, claude-opus, claude-opus-4-6]
  - friendly: Claude Sonnet 4.6
    cli_format: anthropic/claude-sonnet-4-6
    aliases: [sonnet, claude-sonnet, claude-sonnet-4-6]
  - friendly: GPT 5.4
    cli_format: openai/gpt-5.4
    aliases: [gpt-5.4, gpt54]
  - friendly: GPT 5.4 Mini
    cli_format: openai/gpt-5.4-mini
    aliases: [gpt-5.4-mini, gpt54-mini]
YAML

  echo "OpenCode: 7 models probed to $output_file"
}
```

## Codex Probing

**Discovery command:**
```bash
codex exec --help
```

**Probe function:**
```bash
probe_codex() {
  local models_dir="$HOME/.xgh/user_providers/codex"
  local output_file="$models_dir/models.yaml"

  mkdir -p "$models_dir"

  # Generate models.yaml (Codex models are simpler)
  cat > "$output_file" << YAML
agent: codex
cli_binary: codex
last_probed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
models:
  - friendly: GPT 5.4
    cli_format: gpt-5.4
    aliases: [gpt-5.4, gpt54, default]
  - friendly: GPT 5.4 Mini
    cli_format: gpt-5.4-mini
    aliases: [gpt-5.4-mini, gpt54-mini]
  - friendly: GPT 5.3 Codex
    cli_format: gpt-5.3-codex
    aliases: [gpt-5.3-codex]
  - friendly: GPT 5.1 Codex Max
    cli_format: gpt-5.1-codex-max
    aliases: [gpt-5.1-codex-max, o3]
  - friendly: GPT 5.1 Codex Mini
    cli_format: gpt-5.1-codex-mini
    aliases: [gpt-5.1-codex-mini]
YAML

  echo "Codex: 5 models probed to $output_file"
}
```
