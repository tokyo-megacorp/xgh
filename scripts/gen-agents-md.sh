#!/usr/bin/env bash
# gen-agents-md.sh — Generate AGENTS.md from structured YAML config sources.
# Usage: bash scripts/gen-agents-md.sh
# Requires: python3, pyyaml (pip3 install pyyaml)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Verify pyyaml is installed and functional
python3 - <<'PYCHECK'
import sys
try:
    import yaml
    yaml.safe_load("x: 1")
except (ImportError, AttributeError):
    print("ERROR: pyyaml not installed. Run: pip3 install pyyaml", file=sys.stderr)
    sys.exit(1)
PYCHECK

python3 - <<'PYEOF'
import yaml, os, glob, re

ROOT = os.getcwd()

def load(path):
    with open(os.path.join(ROOT, path)) as f:
        return yaml.safe_load(f)

def frontmatter(path):
    with open(path) as f:
        content = f.read()
    m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not m:
        return {}
    try:
        return yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError:
        return {}

def render_condition(when):
    parts = []
    if "source" in when:
        parts.append(when["source"])
    if "type" in when:
        parts.append(when["type"])
    if "match" in when:
        match_parts = [f"{k}={v}" for k, v in when["match"].items()]
        parts.append("match:" + ",".join(match_parts))
    return " / ".join(parts)

proj = load("config/project.yaml")
team = load("config/team.yaml")
wf   = load("config/workflow.yaml")
trg  = load("config/triggers.yaml")
ag   = load("config/agents.yaml")

# Load agent frontmatter from agents/*.md
agent_meta = {}
for path in sorted(glob.glob(os.path.join(ROOT, "agents", "*.md"))):
    fm = frontmatter(path)
    if "name" in fm:
        agent_meta[fm["name"]] = fm

out = []

# Header
out.append("<!-- AUTO-GENERATED — do not edit. Run: bash scripts/gen-agents-md.sh -->")
out.append("")
out.append(f"# AGENTS.md — {proj['name']} ({proj['tagline']}) {proj.get('emoji', '')}")
out.append("")
out.append(f"> Canonical agent instructions for AI systems working on the **{proj['name']}** repository.")
out.append("> All platform-specific files (CLAUDE.md, .github/copilot-instructions.md, etc.) point here.")
out.append("")
out.append("---")
out.append("")

# What is xgh?
out.append(f"## What is {proj['name']}?")
out.append("")
out.append(proj['description'].strip())
out.append("")
out.append("Install via Claude Code plugin:")
out.append("")
out.append("```bash")
out.append(proj['install'].strip())
out.append("```")
out.append("")
out.append("---")
out.append("")

# Tech Stack
out.append("## Tech Stack")
out.append("")
out.append("| Layer | Technology |")
out.append("|-------|-----------|")
for row in proj['tech_stack']:
    out.append(f"| {row['layer']} | {row['technology']} |")
out.append("")
out.append("---")
out.append("")

# Agent Roster — reads from local_agents: section
out.append("## Agent Roster")
out.append("")
out.append("| Agent | Model | Capabilities |")
out.append("|-------|-------|-------------|")
for name, entry in ag.get('local_agents', {}).items():
    model = entry.get('model', '—')
    caps = ", ".join(f"`{c}`" for c in entry.get('capabilities', []))
    out.append(f"| {name} | {model} | {caps} |")
out.append("")
out.append("---")
out.append("")

# Automation Map
out.append("## Automation Map")
out.append("")
out.append("Triggers, workflows, and agents — the full 'what fires when' picture.")
out.append("")
out.append("| Trigger | Condition | Skill | Workflow | Lead Agent |")
out.append("|---------|-----------|-------|----------|-----------|")
for t in trg.get('triggers', []):
    when = t.get('when', {})
    condition = render_condition(when)
    action = t.get('action', {})
    skill = action.get('skill', '—')
    wflow = action.get('workflow', '—')
    agent = action.get('agent', '—')
    out.append(f"| {t['name']} | {condition} | {skill} | {wflow} | {agent} |")
out.append("")
out.append("---")
out.append("")

# Development Guidelines
out.append("## Development Guidelines")
out.append("")
out.append("### General principles")
out.append("")
for i, c in enumerate(team['conventions']['general'], 1):
    out.append(f"{i}. {c}")
out.append("")
out.append("### Coding conventions")
out.append("")
for c in team['conventions']['naming'] + team['conventions']['skills']:
    out.append(f"- {c}")
out.append("")
out.append("### Running tests")
out.append("")
out.append("```bash")
for tc in wf['test_commands']:
    out.append(f"{tc['command']}  # {tc['description']}")
out.append("```")
out.append("")
out.append("---")
out.append("")

# Iron Laws
out.append("## Iron Laws")
out.append("")
for i, law in enumerate(team['iron_laws'], 1):
    out.append(f"{i}. **{law['title']}** — {law['body']}")
out.append("")
out.append("---")
out.append("")

# Superpowers Methodology
out.append("## Superpowers Methodology")
out.append("")
out.append("| Situation | Action |")
out.append("|-----------|--------|")
for row in wf.get('superpowers_table', []):
    out.append(f"| {row['situation']} | {row['action']} |")
out.append("")
out.append("---")
out.append("")

# Key Design Decisions
out.append("## Key Design Decisions")
out.append("")
for i, d in enumerate(proj.get('key_design_decisions', []), 1):
    out.append(f"{i}. **{d['title']}** — {d['body']}")
out.append("")
out.append("---")
out.append("")

# Common Pitfalls
out.append("## Common Pitfalls")
out.append("")
for p in team.get('pitfalls', []):
    out.append(f"- **{p['title']}**: {p['body']}")
out.append("")
out.append("---")
out.append("")

# Implementation Status
out.append("## Implementation Status")
out.append("")
out.append("| Feature | Status |")
out.append("|---------|--------|")
for s in proj.get('implementation_status', []):
    status_label = "Complete" if s.get('status') == 'complete' else "In Progress"
    status_icon = "✅" if s.get('status') == 'complete' else "🔄"
    row = f"| {s['plan']} — {s['title']} | {status_icon} {status_label} |"
    out.append(row)
out.append("")
out.append("---")
out.append("")

with open(os.path.join(ROOT, "AGENTS.md"), "w") as f:
    f.write("\n".join(out))
    f.write("\n")

print(f"AGENTS.md generated ({len(out)} lines)")
PYEOF
