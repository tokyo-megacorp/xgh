#!/usr/bin/env bash
# check-config-drift.sh — Validate that all status:active ingest.yaml github repos
# appear in user_providers/github-cli/provider.yaml sources.
#
# Usage:
#   bash scripts/check-config-drift.sh
#   bash scripts/check-config-drift.sh \
#     --ingest /path/to/ingest.yaml \
#     --provider /path/to/provider.yaml
#
# Exit codes:
#   0 — all checks passed (or warnings only — non-blocking)
#   2 — bad arguments / files not found

set -euo pipefail

INGEST="${XGH_INGEST:-$HOME/.xgh/ingest.yaml}"
PROVIDER="${XGH_PROVIDER:-$HOME/.xgh/user_providers/github-cli/provider.yaml}"

usage() {
  echo "Usage: $0 [--ingest <path>] [--provider <path>]" >&2
}

# Parse optional args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ingest|--provider)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: $1 requires a path argument" >&2
        usage; exit 2
      fi
      if [[ "$1" == "--ingest" ]]; then
        INGEST="$2"
      else
        PROVIDER="$2"
      fi
      shift 2 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [ ! -f "$INGEST" ]; then
  echo "ERROR: ingest.yaml not found at $INGEST" >&2
  exit 2
fi

if [ ! -f "$PROVIDER" ]; then
  echo "WARN: provider.yaml not found at $PROVIDER — skipping drift check"
  exit 0
fi

# Ensure python3 + PyYAML are available — skip gracefully if not.
if ! python3 -c "import yaml" 2>/dev/null; then
  echo "WARN: python3/PyYAML not available — skipping drift check" >&2
  exit 0
fi

# Python does the YAML parsing; we keep the shell script thin.
# Wrap in a subshell so YAML parse errors emit WARN + exit 0 instead of hard failing.
python3 - "$INGEST" "$PROVIDER" <<'PY' || { echo "WARN: YAML parse error — skipping drift check" >&2; exit 0; }
import sys
import yaml

ingest_path = sys.argv[1]
provider_path = sys.argv[2]

with open(ingest_path) as f:
    ingest = yaml.safe_load(f) or {}

with open(provider_path) as f:
    provider = yaml.safe_load(f) or {}

projects = ingest.get("projects", {}) or {}
sources = provider.get("sources", []) or []
provider_repos = {s["repo"] for s in sources if isinstance(s, dict) and s.get("repo")}

warnings = []
for project_name, project in projects.items():
    if not isinstance(project, dict):
        continue
    if project.get("status") != "active":
        continue
    github_repos = project.get("github", []) or []
    for repo in github_repos:
        if repo not in provider_repos:
            warnings.append((project_name, repo))

for project_name, repo in warnings:
    print(f"WARN: project {project_name} ({repo}) is active in ingest.yaml but missing from provider.yaml")

sys.exit(0)
PY
