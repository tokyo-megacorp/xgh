#!/usr/bin/env bash
# xgh SessionStart hook
# Loads context tree, injects top core/validated knowledge files into the session.
# Output: Structured JSON with contextFiles, decisionTable, briefingTrigger
set -euo pipefail

CONTEXT_TREE="${XGH_CONTEXT_TREE:-${XGH_CONTEXT_TREE_PATH:-}}"
XGH_BRIEFING="${XGH_BRIEFING:-off}"
XGH_SCHEDULER="${XGH_SCHEDULER:-off}"

# Walk up to find .xgh/context-tree if not set via env
if [ -z "$CONTEXT_TREE" ]; then
  SEARCH_DIR="$(pwd)"
  while [ "$SEARCH_DIR" != "/" ]; do
    if [ -d "${SEARCH_DIR}/.xgh/context-tree" ]; then
      CONTEXT_TREE="${SEARCH_DIR}/.xgh/context-tree"
      break
    fi
    SEARCH_DIR="$(dirname "$SEARCH_DIR")"
  done
fi

python3 << 'PYEOF'
import json, os, sys, re
from pathlib import Path

context_tree = os.environ.get("XGH_CONTEXT_TREE", os.environ.get("XGH_CONTEXT_TREE_PATH", ""))
briefing_env = os.environ.get("XGH_BRIEFING", "off")
max_files = 5

# Detect dispatch file from command center
dispatch_context = None
dispatch_path = Path.home() / ".xgh" / "inbox" / ".dispatch.md"
if dispatch_path.exists():
    try:
        dispatch_content = dispatch_path.read_text(encoding="utf-8")
        dispatch_context = (
            "PRIORITY CONTEXT (from command center dispatch): "
            + dispatch_content.strip()
        )
        # Remove after reading so it doesn't re-inject on next session start
        dispatch_path.unlink()
    except Exception:
        pass

# Map briefing env values
if briefing_env in ("auto", "1"):
    briefing_trigger = "full"
elif briefing_env == "compact":
    briefing_trigger = "compact"
else:
    briefing_trigger = "off"

scheduler_env = os.environ.get("XGH_SCHEDULER", "off")
scheduler_trigger = "on" if scheduler_env in ("on", "1") else "off"

if scheduler_trigger == "on":
    scheduler_instructions = (
        "SCHEDULER — act on this immediately and silently, no confirmation needed: "
        "Call CronCreate three times to set up background jobs for this session: "
        "(1) cron='*/5 * * * *', prompt='/xgh-retrieve', recurring=true  "
        "(2) cron='*/30 * * * *', prompt='/xgh-analyze', recurring=true  "
        "(3) cron='0 * * * *', prompt='/xgh-deep-retrieve', recurring=true  "
        "These will auto-expire after 3 days. Use /xgh-schedule to manage them."
    )
else:
    scheduler_instructions = None

decision_table = [
    "Before writing code: run lcm_search first.",
    "After significant work: extract key learnings → lcm_store.",
    "For architectural choices: store rationale with lcm_store(text, ['reasoning'])."
]

# No context tree found
if not context_tree or not os.path.isdir(context_tree):
    output = {
        "result": "xgh: session-start loaded 0 context files",
        "contextFiles": [],
        "decisionTable": decision_table,
        "briefingTrigger": briefing_trigger,
        "schedulerTrigger": scheduler_trigger,
        "schedulerInstructions": scheduler_instructions,
        "dispatchContext": dispatch_context
    }
    print(json.dumps(output))
    sys.exit(0)

# Walk the context tree for .md files
context_path = Path(context_tree)
entries = []

for md_file in context_path.rglob("*.md"):
    rel = md_file.relative_to(context_path)
    rel_str = str(rel)

    # Exclude _index.md and _archived/
    if rel.name == "_index.md":
        continue
    if "_archived" in rel.parts:
        continue

    try:
        content = md_file.read_text(encoding="utf-8")
    except Exception:
        continue

    # Parse frontmatter
    title = rel.stem
    importance = 0
    maturity = "draft"
    body = content

    fm_match = re.match(r"^---\s*\n(.*?)\n---\s*\n(.*)", content, re.DOTALL)
    if fm_match:
        fm_text = fm_match.group(1)
        body = fm_match.group(2)
        for line in fm_text.splitlines():
            if line.startswith("title:"):
                title = line.split(":", 1)[1].strip().strip("\"'")
            elif line.startswith("importance:"):
                try:
                    importance = int(line.split(":", 1)[1].strip())
                except ValueError:
                    pass
            elif line.startswith("maturity:"):
                maturity = line.split(":", 1)[1].strip().strip("\"'")

    # Compute score: maturity_rank * 100 + importance
    maturity_rank = {"core": 3, "validated": 2, "draft": 1}.get(maturity, 0)
    score = maturity_rank * 100 + importance

    # Extract 3-line excerpt (first 3 non-empty lines of body)
    body_lines = [l.strip() for l in body.splitlines() if l.strip()]
    excerpt = "\n".join(body_lines[:3])

    entries.append({
        "path": rel_str,
        "title": title,
        "importance": importance,
        "maturity": maturity,
        "excerpt": excerpt,
        "_score": score
    })

# Sort by score descending, take top N
entries.sort(key=lambda e: -e["_score"])
top = entries[:max_files]

# Remove internal _score key
context_files = []
for e in top:
    context_files.append({
        "path": e["path"],
        "title": e["title"],
        "importance": e["importance"],
        "maturity": e["maturity"],
        "excerpt": e["excerpt"]
    })

output = {
    "result": f"xgh: session-start loaded {len(context_files)} context files",
    "contextFiles": context_files,
    "decisionTable": decision_table,
    "briefingTrigger": briefing_trigger,
    "schedulerTrigger": scheduler_trigger,
    "schedulerInstructions": scheduler_instructions,
    "dispatchContext": dispatch_context
}

print(json.dumps(output))
PYEOF
exit 0
