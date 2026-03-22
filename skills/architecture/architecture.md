---
name: xgh:architecture
description: >
  Higher-level architectural analysis. Reads index inventory, produces structured
  definitions of how modules connect — boundaries, dependency graph, critical paths,
  and public surfaces.
type: flexible
mcp_dependencies: [mcp__lossless-claude__lcm_store, mcp__lossless-claude__lcm_search]
triggers:
  - when the user runs /xgh-architecture
  - when the user says "analyze architecture", "architecture analysis", "show architecture"
  - when the user says "how are the modules connected", "map the codebase"
  - when invoked after /xgh:index completes
---

# xgh:architecture — Codebase Architecture Analysis

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
    import subprocess
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

- If output is `NO_INGEST_YAML` → stop: "No ingest config found. Run `/xgh-init` first."
- If output is `NO_MATCH` → stop: "No project config found for this repo. Run `/xgh:config add-project` to register it."

Save the matched project name as `<repo-name>`.

## Step 2 — Hard prerequisite: index freshness

### 2a — Search lossless-claude for index entries

Call `mcp__lossless-claude__lcm_search` with query `xgh:index` and tag filter `["xgh:index", "<repo-name>"]`.

- If no results returned → stop:
  > "No codebase index found for `<repo-name>`. Run `/xgh:index` first."

### 2b — Check index age from ingest.yaml

```bash
python3 -c "
import sys, os, json
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
cfg = data.get('projects', {}).get(name, {})
last_run = cfg.get('index', {}).get('last_run')
if not last_run:
    print('NEVER')
    sys.exit(0)

dt = datetime.fromisoformat(last_run)
now = datetime.now(timezone.utc)
days = (now - dt).days
print(days)
" "<repo-name>"
```

- If `NEVER` → stop: "Index timestamp missing for `<repo-name>`. Run `/xgh:index` first."
- If days > 60 → stop: "Index is N days old (>60 day limit). Run `/xgh:index` first."
- If days > 14 → warn: "Index is N days old. Consider re-running `/xgh:index` for fresh results." (continue)

## Step 3 — Parse mode

Read `$ARGUMENTS`. Default to `quick` if not provided.

- Accepted values: `quick`, `full`
- If unrecognized value provided → default to `quick` and note it.

Save as `<mode>`.

## Step 4 — Read stack and surfaces

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

Save `<stack>` and `<surfaces>`.

## Step 5 — Quick mode artifacts

Produce these 3 artifacts for both `quick` and `full` mode:

### Artifact 1: module-boundaries

Identify all modules/packages in the codebase. For each module:
- What it owns (its responsibility)
- What it exposes to other modules (public API/interface)
- Which other modules it depends on (seams)

Use the lossless-claude index memories (from `lcm_search` with tag `xgh:index`) as primary source. Supplement with Glob/Grep if needed.

Format as a table:
```
| Module | Owns | Exposes | Depends On |
|--------|------|---------|------------|
```

### Artifact 2: public-surfaces

Enumerate all external-facing surfaces based on `<surfaces>` from config:
- **cli**: Commands, flags, subcommands
- **api**: HTTP endpoints (method + path + purpose)
- **web**: UI routes/pages
- **mobile**: Screens, deep links
- **library/sdk**: Exported symbols, public types, entry points
- **plugin**: Extension points, hooks

### Artifact 3: integration-points

Map all external system dependencies:
- Databases (type, what stored)
- External APIs (name, purpose)
- Message queues / event buses
- Filesystems / object storage
- Auth providers

## Step 6 — Full mode additional artifacts

Only produce these if `<mode>` is `full`:

### Artifact 4: dependency-graph

Internal dependency graph:
- Directed edges: which module imports/calls which
- Identify circular dependencies (flag as ⚠)
- Identify hub modules (high fan-in — flag as critical)

External dependency graph:
- Direct external dependencies from manifest files (`package.json`, `Cargo.toml`, `go.mod`, `Package.swift`, `build.gradle`)
- Group by category: testing, networking, storage, UI, build tooling

### Artifact 5: critical-paths

Key user or data journeys through the system. For each path:
- Name (e.g. "user login", "data ingestion", "PR review")
- Entry point → module chain → exit point
- Estimated complexity (low/medium/high)

### Artifact 6: test-landscape

Map existing test coverage:
- Test frameworks in use (detect from manifest and test file patterns)
- Test directories and what they cover
- Coverage gaps (modules with no test files)
- Integration vs unit vs e2e breakdown

## Step 7 — Stack-specific analysis

Run additional analysis based on `<stack>`:

### iOS / Swift
- Coordinator or navigation pattern used (check for Coordinator classes, NavigationController hierarchy)
- SPM modules (read `Package.swift`)
- Feature flags (search for flag/toggle patterns)
- DI patterns (Resolver, Swinject, manual injection)

### Android / Kotlin
- Activity/Fragment hierarchy
- Dagger/Hilt graph (search for `@Module`, `@Component`, `@HiltAndroidApp`)
- Navigation graph (`res/navigation/`)
- ViewModel / LiveData / StateFlow patterns

### TypeScript / React
- Component tree (top-level pages → layout → feature components)
- State management (Redux, Zustand, Jotai, Context — detect from imports)
- Custom hook conventions (prefix `use`, location, categorization)
- API layer organization (fetch wrappers, React Query, SWR)

### Go
- Package boundaries and import graph
- Interface contracts (key interfaces and their implementations)
- Error handling patterns (sentinel errors, wrapped errors, custom types)

### Rust
- Module tree (`mod` declarations, `lib.rs` / `main.rs` structure)
- Trait implementations (key traits and implementing types)
- Feature flags (`[features]` in `Cargo.toml`)

### All stacks
- API routes (detect framework: Express, Gin, Axum, Vapor, etc.)
- Service layer boundaries
- CI/CD config (`.github/workflows/`, `Jenkinsfile`, `Fastfile`, etc.)

## Artifact availability table

| Artifact | quick | full |
|----------|-------|------|
| module-boundaries | ✓ | ✓ |
| public-surfaces | ✓ | ✓ |
| integration-points | ✓ | ✓ |
| dependency-graph | — | ✓ |
| critical-paths | — | ✓ |
| test-landscape | — | ✓ |

## Step 8 — Store artifacts to lossless-claude

For each artifact produced, call `mcp__lossless-claude__lcm_store`:

```
[ARCHITECTURE][<artifact-name>] <repo-name>
<artifact content as structured summary>
Mode: <quick|full>
Stack: <stack>
Generated: <ISO timestamp>
```

Tags: `["xgh:architecture", "<artifact-name>", "<repo-name>"]`

Do not store raw file content. Store synthesized, structured summaries only.

## Step 9 — Update ingest.yaml

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

name, mode = sys.argv[1], sys.argv[2]
path = os.path.expanduser('~/.xgh/ingest.yaml')
data = yaml.safe_load(open(path))
arch = data.setdefault('projects', {}).setdefault(name, {}).setdefault('architecture', {})
arch['last_run'] = datetime.now(timezone.utc).isoformat()
arch['mode'] = mode
yaml.dump(data, open(path, 'w'), default_flow_style=False, allow_unicode=True)
print('updated')
" "<repo-name>" "<mode>"
```

## Step 10 — Completion

Print a summary:
```
Architecture analysis complete for <repo-name>
  Mode: <quick|full>
  Stack: <stack>
  Artifacts stored: <count>
  Modules mapped: <count>
```

Then suggest next step:
- If mode was `quick`: *Run `/xgh:architecture full` for dependency graph, critical paths, and test landscape.*
- If mode was `full`: *Run `/xgh:test-builder` to generate tests based on the architecture map.*
