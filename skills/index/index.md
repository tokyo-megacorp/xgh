---
name: xgh:index
description: >
  Raw codebase inventory — extracts module list, key files, and naming conventions
  into lossless-claude memory. Reads stack and surfaces from ~/.xgh/ingest.yaml.
type: flexible
triggers:
  - when the user runs /xgh-index
  - when the user says "index repo", "index codebase", "scan the codebase"
  - when invoked by ingest-track after adding a GitHub repo
---

# xgh:index — Codebase Inventory

## Step 1 — Resolve project from ingest.yaml

Get the git remote of the current directory:

```bash
git -C . remote get-url origin 2>/dev/null || git -C . remote get-url upstream 2>/dev/null
```

Match the remote URL against `projects.<name>.github` in `~/.xgh/ingest.yaml`:

```bash
python3 -c "
import sys, os
try:
    import yaml
except ImportError:
    import subprocess, importlib
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'pyyaml', '-q'])
    import yaml

remote = sys.argv[1].strip()
path = os.path.expanduser('~/.xgh/ingest.yaml')
try:
    data = yaml.safe_load(open(path))
except FileNotFoundError:
    print('NO_INGEST_YAML')
    sys.exit(0)

projects = data.get('projects', {})
for name, cfg in projects.items():
    github_entries = cfg.get('github', [])
    if isinstance(github_entries, str):
        github_entries = [github_entries]
    for gh in github_entries:
        if gh in remote or remote in gh:
            print(name)
            sys.exit(0)

print('NO_MATCH')
" "<remote-url>"
```

- If output is `NO_INGEST_YAML` or `NO_MATCH` → stop and tell the user:
  > "No project config found for this repo. Run `/xgh:config add-project` to register it."

Save the matched project name as `<repo-name>`.

## Step 2 — Read stack and surfaces

```bash
python3 -c "
import sys, os, json
try:
    import yaml
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'pyyaml', '-q'])
    import yaml

name = sys.argv[1]
path = os.path.expanduser('~/.xgh/ingest.yaml')
data = yaml.safe_load(open(path))
cfg = data.get('projects', {}).get(name, {})
result = {
    'stack': cfg.get('stack'),
    'surfaces': cfg.get('surfaces'),
}
print(json.dumps(result))
" "<repo-name>"
```

- If `stack` is null or missing → stop and tell the user:
  > "Stack not set for `<repo-name>`. Run `/xgh:config set` to configure it."
- If `surfaces` is null or missing → stop and tell the user:
  > "Surfaces not set for `<repo-name>`. Run `/xgh:config set` to configure it."

Save `<stack>` and `<surfaces>` for use in memory entries.

## Step 3 — Directory structure

Use `Glob` with pattern `**/*` at depth 2 to map top-level layout. List the top-level directories and their immediate children.

## Step 4 — Key files

Read the following if present:
- Manifests: `Package.swift`, `package.json`, `build.gradle`, `Cargo.toml`, `go.mod`
- Main entry point (e.g. `main.swift`, `index.ts`, `main.go`, `App.kt`)
- `README.md` or `README`

## Step 5 — Module inventory

For each top-level module/package directory:
- Note its purpose from file names and README hints
- List 2–4 key files

## Step 6 — Naming conventions

Sample 5–10 files across the repo. Extract:
- Type/class naming pattern (e.g. CamelCase, PascalCase)
- Function/method naming pattern (e.g. camelCase, snake_case)
- File naming pattern (e.g. FeatureName+Extension.swift, feature.service.ts)

## Step 7 — Store to memory

For each module found, call `lcm_store` with a summary in this exact format:

```
[REPO][MODULE] <module-name>: <one-sentence purpose>
Key files: path/to/file1, path/to/file2
Pattern: <naming or architectural pattern observed>
Stack: <stack from ingest.yaml>
Indexed: <ISO date>
```

Tags: `["xgh:index", "<repo-name>"]`

Do not pass raw file content to `lcm_store`. Synthesize a concise summary for each module.

## Step 8 — Update index timestamp

Update `index.last_run` in `~/.xgh/ingest.yaml` for the resolved project:

```bash
python3 -c "
import sys, os
from datetime import datetime, timezone
try:
    import yaml
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'pyyaml', '-q'])
    import yaml

name = sys.argv[1]
path = os.path.expanduser('~/.xgh/ingest.yaml')
data = yaml.safe_load(open(path))
data.setdefault('projects', {}).setdefault(name, {}).setdefault('index', {})['last_run'] = datetime.now(timezone.utc).isoformat()
yaml.dump(data, open(path, 'w'), default_flow_style=False, allow_unicode=True)
print('updated')
" "<repo-name>"
```

## Step 9 — Completion

Print a summary:
```
Index complete for <repo-name>
  Stack: <stack>
  Surfaces: <surfaces>
  Modules indexed: <count>
  Memories stored: <count>
```

Then ask: "Index complete. Run `/xgh:architecture`? [y/n]"
