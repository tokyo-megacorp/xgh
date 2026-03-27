# Agent Frontmatter Reference

Agent files in xgh use YAML frontmatter to declare metadata. Skills should read and respect this metadata when spawning or working with agents.

## Frontmatter Schema

```yaml
---
name: <string>                # Agent identifier (e.g., "code-reviewer")
description: |                # Markdown description of agent usage
  Multi-line description of when and why to use this agent.
  Include examples if relevant.

model: <string>               # Model: "haiku" | "sonnet" | "opus" | "sonnet4"
                              # (default: from skill settings or sonnet)
capabilities: [<string>]      # Semantic tags: [code-review, architecture, investigation, etc.]
color: <string>               # UI color hint (default: default, or custom hex/name)
tools: [<string>]             # List of available tools (Read, Grep, Bash, etc.)

# Optional extended metadata
effort: <string>              # "quick" | "moderate" | "intensive" (for planning)
focus_area: <string>          # Domain: ios, backend, security, docs, etc.
cost_model: <string>          # "efficient" | "balanced" | "thorough"
---
```

## Reading Frontmatter in Skills

When a skill needs to spawn or configure an agent, extract frontmatter:

### 1. Extract YAML header

```bash
# Extract YAML frontmatter from agent file
agent_file="$1"
frontmatter=$(awk '/^---$/{flag=!flag;next}flag' "$agent_file" | head -20)
```

### 2. Parse key fields

Use `yq` or native parsing:

```bash
name=$(echo "$frontmatter" | grep "^name:" | cut -d' ' -f2)
model=$(echo "$frontmatter" | grep "^model:" | cut -d' ' -f2)
capabilities=$(echo "$frontmatter" | grep "^capabilities:" | tr -d '[]' | sed 's/capability://g')
```

Or in Python:

```python
import yaml

def read_agent_frontmatter(agent_file_path):
    with open(agent_file_path) as f:
        # Skip to frontmatter
        if f.readline().strip() != "---":
            return {}

        # Read until closing ---
        frontmatter_lines = []
        for line in f:
            if line.strip() == "---":
                break
            frontmatter_lines.append(line)

        return yaml.safe_load("".join(frontmatter_lines)) or {}
```

### 3. Use in skill context

When spawning an agent:

```bash
# Read frontmatter
fm=$(read_agent_frontmatter "$agent_file")

# Extract model, default to "sonnet"
model=$(echo "$fm" | yq '.model // "sonnet"')

# Extract capabilities for context
capabilities=$(echo "$fm" | yq '.capabilities | join(", ")')

# Pass to agent spawn with appropriate model
spawn_agent --model "$model" --agent "$agent_file"
```

## Common Frontmatter Patterns

| Field | Usage | Example |
|-------|-------|---------|
| `model` | Route to correct Claude version | `sonnet` for review, `haiku` for triage |
| `capabilities` | Filter agents by skill type | Skill needs [code-review] → use code-reviewer agent |
| `tools` | Predict what agent can access | Agent has [Bash] → can run shell commands |
| `effort` | Time/cost estimation | "quick" agents for fast triage, "intensive" for deep review |
| `focus_area` | Domain-specific routing | iOS skill → prefer ios-lead agent |

## Team Lead Agent Metadata

Team Lead agents extend the base schema with context:

```yaml
---
name: team-lead
description: "Orchestrator for [project-name]. Sets crons, manages project backlog, delegates work."
model: sonnet
capabilities: [orchestration, delegation, context-gathering]
color: default
tools: [Read, Grep, Bash, Skill]

# Team Lead specific
team_context:
  project: xgh                    # Project this lead owns
  repo_path: ~/Developer/xgh
  github_project: "xgh — Development"
  cron_retrieve: "*/30 * * * *"   # Retrieve interval
  cron_analyze: "0 * * * *"       # Analyze interval

on_spawn:
  - setup_crons
  - gather_context
  - report_status
---
```

Skills should read `team_context.project` and `on_spawn` to understand what the agent will do.

## Skills Using Frontmatter

These xgh skills should read and respect agent frontmatter:

- **dispatch** — Route task to agent with matching capability + preferred model
- **team** (agent-collaboration) — Spawn team lead agents, respecting on_spawn hooks
- **ship-prs** — Find code-review agents, use preferred model
- **implement** — Spawn implementation agents with correct effort level

## Related Files

- Agent definitions: `~/Developer/xgh/agents/*.md`
- Base template: `~/.claude/org/team-lead-template.md`
- Skill integration example: `~/Developer/xgh/skills/dispatch/dispatch.md`
