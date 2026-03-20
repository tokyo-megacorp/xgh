#!/usr/bin/env bash
# xgh SessionStart hook
# Loads context tree, injects top core/validated knowledge files into the session.
# Output: Structured JSON with contextFiles, decisionTable, briefingTrigger
set -euo pipefail

CONTEXT_TREE="${XGH_CONTEXT_TREE:-${XGH_CONTEXT_TREE_PATH:-}}"

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

# ── Retention cleanup ──
_xgh_home="${HOME}/.xgh"
if [ -d "${_xgh_home}/inbox/processed" ]; then
  find "${_xgh_home}/inbox/processed/" -type f -mtime +7 -delete 2>/dev/null || true
fi
if [ -d "${_xgh_home}/digests" ]; then
  find "${_xgh_home}/digests/" -type f -mtime +30 -delete 2>/dev/null || true
fi
if [ -d "${_xgh_home}/logs" ]; then
  find "${_xgh_home}/logs/" -type f -mtime +7 -delete 2>/dev/null || true
fi

python3 << 'PYEOF'
import json, os, sys, re, glob as _glob
from pathlib import Path

context_tree = os.environ.get("XGH_CONTEXT_TREE", os.environ.get("XGH_CONTEXT_TREE_PATH", ""))
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

# Briefing always available
briefing_trigger = "full"

# Scheduler: check for pause file, otherwise always on
scheduler_paused = Path.home().joinpath(".xgh", "scheduler-paused").exists()
scheduler_trigger = "paused" if scheduler_paused else "on"

# Provider detection for scheduler lanes
has_bash_providers = bool(_glob.glob(str(Path.home() / ".xgh/providers/*/fetch.sh")))
has_mcp_providers = any(
    "mode: mcp" in open(f).read()
    for f in _glob.glob(str(Path.home() / ".xgh/providers/*/provider.yaml"))
)

if scheduler_trigger == "on":
    scheduler_instructions = (
        "SCHEDULER — act on this immediately and silently, no confirmation needed: "
        "Call CronCreate to set up background jobs for this session: "
    )
    job_num = 1
    if has_bash_providers:
        scheduler_instructions += (
            f"({job_num}) cron='*/5 * * * *', prompt='bash ~/.xgh/scripts/retrieve-all.sh || true', recurring=true  "
        )
        job_num += 1
    if has_mcp_providers:
        scheduler_instructions += (
            f"({job_num}) cron='*/5 * * * *', prompt='Read all provider.yaml files in ~/.xgh/providers/. "
            "For each with mode: mcp, call the MCP tools listed in mcp.tools with params filled "
            "from sources and cursor, write results as inbox .md files to ~/.xgh/inbox/, update "
            "cursor files. No analysis — fetch only.', recurring=true  "
        )
        job_num += 1
    scheduler_instructions += (
        f"({job_num}) cron='*/30 * * * *', prompt='/xgh-analyze', recurring=true  "
        "These will auto-expire after 3 days. Use /xgh-schedule to manage them."
    )
else:
    scheduler_instructions = None

# Read custom scheduled jobs from ingest.yaml
custom_jobs = []
ingest_path = Path.home() / ".xgh" / "ingest.yaml"
if ingest_path.exists():
    try:
        import subprocess as _sp
        _yq = _sp.run(
            ["yq", "-o=json", ".schedule.jobs // []", str(ingest_path)],
            capture_output=True, text=True
        )
        if _yq.returncode == 0 and _yq.stdout.strip() not in ("", "null", "[]"):
            custom_jobs = json.loads(_yq.stdout)
    except Exception:
        pass

if scheduler_trigger == "on" and custom_jobs:
    for idx, j in enumerate(custom_jobs, start=4):
        skill = j.get("skill", "")
        cron = j.get("cron", "")
        if skill and cron:
            scheduler_instructions += (
                f" ({idx}) cron='{cron}', "
                f"prompt='{skill}', recurring=true "
            )

# Context-mode enforcement delegated to context-mode plugin's own hooks.
# No tracking state or decision table needed here.

# No context tree found
if not context_tree or not os.path.isdir(context_tree):
    output = {
        "result": "xgh: session-start loaded 0 context files",
        "contextFiles": [],
        "briefingTrigger": briefing_trigger,
        "schedulerTrigger": scheduler_trigger,
        "schedulerInstructions": scheduler_instructions,
        "schedulerCustomJobs": custom_jobs,
        "dispatchContext": dispatch_context,
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
    "briefingTrigger": briefing_trigger,
    "schedulerTrigger": scheduler_trigger,
    "schedulerInstructions": scheduler_instructions,
    "schedulerCustomJobs": custom_jobs,
    "dispatchContext": dispatch_context,
}

print(json.dumps(output))
PYEOF
exit 0
