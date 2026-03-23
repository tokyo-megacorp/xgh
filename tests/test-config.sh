#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }

# Plugin subdirs (agents, skills, commands, hooks live at root)
assert_file_exists "hooks/.gitkeep"
for d in skills commands agents; do
  if [ -d "$d" ] && [ "$(ls -A "$d")" ]; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $d is empty or missing"
    FAIL=$((FAIL+1))
  fi
done


# --- agents.yaml: opencode entry ---
assert_contains "config/agents.yaml" "opencode:"
assert_contains "config/agents.yaml" "opencode run"
assert_contains "config/agents.yaml" "auto_detect: opencode"

# --- agents.yaml: registry fields on codex + gemini ---
assert_contains "config/agents.yaml" "skill_dir:"
assert_contains "config/agents.yaml" "rules_file:"
assert_contains "config/agents.yaml" "auto_detect:"
assert_contains "config/agents.yaml" "auto_detect: codex"
assert_contains "config/agents.yaml" "auto_detect: gemini"

# --- copilot-pr-review: command + skill registration ---
assert_file_exists "commands/copilot-pr-review.md"
assert_file_exists "skills/copilot-pr-review/copilot-pr-review.md"
assert_contains "commands/copilot-pr-review.md" "copilot-pr-review"

# --- watch-prs: command + skill registration ---
assert_file_exists "commands/watch-prs.md"
assert_file_exists "skills/watch-prs/watch-prs.md"
assert_contains "commands/watch-prs.md" "watch-prs"

# --- ship-prs: command + skill registration ---
assert_file_exists "commands/ship-prs.md"
assert_file_exists "skills/ship-prs/ship-prs.md"
assert_contains "commands/ship-prs.md" "ship-prs"
assert_contains "skills/ship-prs/ship-prs.md" "^name: xgh:ship-prs"
assert_contains "skills/ship-prs/ship-prs.md" "pause"
assert_contains "skills/ship-prs/ship-prs.md" "dry-run"
assert_contains "skills/ship-prs/ship-prs.md" "fix_cycle_count"

# --- config: command + skill registration ---
assert_file_exists "commands/config.md"
assert_file_exists "skills/config/config.md"
assert_contains "commands/config.md" "name: xgh-config"

# --- architecture: command + skill registration ---
assert_file_exists "commands/architecture.md"
assert_file_exists "skills/architecture/architecture.md"
assert_contains "commands/architecture.md" "name: xgh-architecture"

# --- test-builder: command + skill registration ---
assert_file_exists "commands/test-builder.md"
assert_file_exists "skills/test-builder/test-builder.md"
assert_contains "commands/test-builder.md" "name: xgh-test-builder"

# --- prompt test coverage for new skills (all variants) ---
assert_file_exists "tests/skill-triggering/prompts/copilot-pr-review.txt"
assert_file_exists "tests/skill-triggering/prompts/copilot-pr-review-2.txt"
assert_file_exists "tests/skill-triggering/prompts/copilot-pr-review-3.txt"
assert_file_exists "tests/skill-triggering/prompts/watch-prs.txt"
assert_file_exists "tests/skill-triggering/prompts/watch-prs-2.txt"
assert_file_exists "tests/skill-triggering/prompts/watch-prs-3.txt"
assert_file_exists "tests/skill-triggering/prompts/ship-prs.txt"
assert_file_exists "tests/skill-triggering/prompts/ship-prs-2.txt"
assert_file_exists "tests/skill-triggering/prompts/ship-prs-3.txt"
assert_file_exists "tests/skill-triggering/prompts/config.txt"
assert_file_exists "tests/skill-triggering/prompts/config-2.txt"
assert_file_exists "tests/skill-triggering/prompts/config-3.txt"
assert_file_exists "tests/skill-triggering/prompts/architecture.txt"
assert_file_exists "tests/skill-triggering/prompts/architecture-2.txt"
assert_file_exists "tests/skill-triggering/prompts/architecture-3.txt"
assert_file_exists "tests/skill-triggering/prompts/test-builder.txt"
assert_file_exists "tests/skill-triggering/prompts/test-builder-2.txt"
assert_file_exists "tests/skill-triggering/prompts/test-builder-3.txt"

assert_file_exists "config/project.yaml"
assert_contains "config/project.yaml" "name: xgh"
assert_contains "config/project.yaml" "xgh: Claude on the fastlane"
assert_contains "config/project.yaml" "tech_stack:"
assert_contains "config/project.yaml" "install:"
assert_contains "config/project.yaml" "key_design_decisions:"
assert_contains "config/project.yaml" "lossless-claude"
assert_contains "config/project.yaml" "preferences:"
assert_contains "config/project.yaml" "pair_programming:"
assert_contains "config/project.yaml" "xgh:codex"

assert_file_exists "config/team.yaml"
assert_contains "config/team.yaml" "conventions:"
assert_contains "config/team.yaml" "iron_laws:"
assert_contains "config/team.yaml" "pitfalls:"
assert_contains "config/team.yaml" "Never skip the test"
assert_contains "config/team.yaml" "lower_snake_case"
assert_contains "config/team.yaml" 'YAML keys: `snake_case`'
assert_contains "config/team.yaml" '`triggers`'

assert_file_exists "config/workflow.yaml"
assert_contains "config/workflow.yaml" "phases:"
assert_contains "config/workflow.yaml" "defaults:"
assert_contains "config/workflow.yaml" "test_commands:"
assert_contains "config/workflow.yaml" "superpowers_table:"
assert_contains "config/workflow.yaml" "feat/, fix/, docs/"

assert_file_exists "config/triggers.yaml"
assert_contains "config/triggers.yaml" "triggers:"
assert_contains "config/triggers.yaml" "installed_by: xgh"
assert_contains "config/triggers.yaml" "pr-opened"
assert_contains "config/triggers.yaml" "digest-ready"
assert_contains "config/triggers.yaml" "security-alert"

assert_contains "agents/code-reviewer.md" "model: sonnet"
assert_contains "agents/code-reviewer.md" "color: default"
assert_contains "agents/code-reviewer.md" "tools:"
assert_contains "agents/pr-reviewer.md" "model: sonnet"
assert_contains "config/agents.yaml" "local_agents:"
assert_contains "config/agents.yaml" "type: agent"

assert_file_exists "scripts/gen-agents-md.sh"
assert_contains "scripts/gen-agents-md.sh" "pyyaml"
assert_contains "scripts/gen-agents-md.sh" "AUTO-GENERATED"

assert_contains "AGENTS.md" "<!-- AUTO-GENERATED"
assert_contains "AGENTS.md" "## Agent Roster"
assert_contains "AGENTS.md" "| Agent | Model | Capabilities |"
assert_contains "AGENTS.md" "## Automation Map"
assert_contains "AGENTS.md" "| Trigger | Condition | Skill | Workflow | Lead Agent |"
assert_contains "AGENTS.md" "## Iron Laws"
assert_contains "AGENTS.md" "## Implementation Status"
assert_contains "AGENTS.md" "### Branch strategy"
assert_contains "AGENTS.md" 'Feature work: branch off `develop`'

assert_contains ".xgh/specs/2026-03-21-xgh-agents-design.md" '| 1 | `code-reviewer` | sonnet |'
assert_contains ".xgh/specs/2026-03-21-xgh-agents-design.md" "sonnet/haiku/opus"
assert_contains ".xgh/xgh.md" 'Source: loaded by `CLAUDE.local.md` via `@` reference.'
assert_contains "tests/skill-triggering/prompts/track.txt" "add this repo to xgh monitoring"
assert_contains "tests/skill-triggering/prompts/briefing.txt" "/xgh-briefing"

HAVE_PYYAML=true
python3 -c "import yaml" 2>/dev/null || HAVE_PYYAML=false

if [ "$HAVE_PYYAML" = "true" ]; then

TMP_REPO="$(mktemp -d)"
trap 'rm -rf "$TMP_REPO"' EXIT
mkdir -p "$TMP_REPO/scripts" "$TMP_REPO/config" "$TMP_REPO/agents"
cp scripts/gen-agents-md.sh "$TMP_REPO/scripts/"
cp config/project.yaml config/team.yaml config/workflow.yaml config/triggers.yaml config/agents.yaml "$TMP_REPO/config/"
cp agents/*.md "$TMP_REPO/agents/"

python3 - "$TMP_REPO/config/agents.yaml" <<'PY'
from pathlib import Path
import sys
import yaml
path = Path(sys.argv[1])
data = yaml.safe_load(path.read_text())
data["local_agents"] = {}
path.write_text(yaml.safe_dump(data, sort_keys=False))
PY

python3 - "$TMP_REPO/agents/code-reviewer.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("model: sonnet", "model: haiku", 1)
text = text.replace(
    "capabilities: [code-review, architecture, conventions]",
    "capabilities: [frontmatter-source]",
    1,
)
path.write_text(text)
PY

cat > "$TMP_REPO/agents/bad-frontmatter.md" <<'EOF'
---
name: bad-frontmatter
description: "unterminated
capabilities: [still-present]
---
Broken frontmatter fixture for generator warning tests.
EOF

if (cd "$TMP_REPO" && bash scripts/gen-agents-md.sh >/dev/null 2>"$TMP_REPO/gen.stderr"); then
  PASS=$((PASS+1))
else
  echo "FAIL: generator fixture run exited non-zero"
  FAIL=$((FAIL+1))
fi
assert_contains "$TMP_REPO/gen.stderr" "WARNING:"
assert_contains "$TMP_REPO/gen.stderr" "bad-frontmatter.md:"
assert_contains "$TMP_REPO/AGENTS.md" '| code-reviewer | haiku | `frontmatter-source` |'

else
  echo "SKIP: pyyaml not installed — skipping generator fixture tests"
fi

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
