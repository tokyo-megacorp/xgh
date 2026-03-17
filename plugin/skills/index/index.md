---
name: xgh:index
description: >
  Codebase architecture extraction. Scans a repository to extract modules, patterns,
  navigation flows, naming conventions, and feature flags into lossless-claude memory.
  Supports quick (~5 min) and full (~30 min) modes.
type: flexible
triggers:
  - when the user runs /xgh-index
  - when the user says "index repo", "index codebase", "scan the codebase"
  - when invoked by ingest-track after adding a GitHub repo
mcp_dependencies:
  - mcp__lossless-claude__lcm_store
  - mcp__lossless-claude__lcm_search
---

## Preamble — Execution mode

Before starting, check whether the user has a saved execution mode preference for this skill.

**Step P1 — Read preference:**
```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.xgh/prefs.json')
try:
    p = json.load(open(path))
    v = p.get('skill_mode', {}).get('index')
    print(json.dumps(v) if v else '')
except: print('')
"
```
If output is non-empty JSON, extract `mode` and `autonomy` (if present) and skip to **Dispatch** below.

**Step P2 — If not set, ask the user (one question at a time):**
- "Run **index** in background (returns summary when done) or interactive? [b/i, default: i]"
- If "b": "Check in with a quick question before starting, or fire-and-forget? [c/f, default: c]"

**Step P3 — Write preference:**
```bash
python3 -c "
import json, os, sys
mode, autonomy = sys.argv[1], sys.argv[2]
path = os.path.expanduser('~/.xgh/prefs.json')
os.makedirs(os.path.dirname(path), exist_ok=True)
try: p = json.load(open(path))
except: p = {}
p.setdefault('skill_mode', {})
entry = {'mode': mode} if mode == 'interactive' else {'mode': mode, 'autonomy': autonomy}
p['skill_mode']['index'] = entry
json.dump(p, open(path, 'w'), indent=2)
" "<mode>" "<autonomy>"
```

**Step P4 — Flag overrides** (check the raw invocation text; do not update prefs.json):
- contains `--bg` → use background mode
- contains `--interactive` or `--fg` → use interactive mode
- contains `--checkin` → use check-in autonomy
- contains `--auto` → use fire-and-forget autonomy
- contains `--reset` → run `python3 -c "import json,os; p=json.load(open(os.path.expanduser('~/.xgh/prefs.json'))); p.get('skill_mode',{}).pop('index',None); json.dump(p,open(os.path.expanduser('~/.xgh/prefs.json'),'w'),indent=2)"` then re-prompt

**Dispatch:**

**Interactive mode** → proceed with the skill normally (continue to the rest of this file).

**Background / check-in mode:**
1. Ask at most 2 essential clarifying questions in the main session.
2. Collect context: user's request verbatim, current branch (`git branch --show-current`), recent log (`git log --oneline -5`), any relevant file paths mentioned.
3. Dispatch via Agent tool with `run_in_background: true`. Prompt must be fully self-contained.
4. Reply: "Index running in background — I'll post findings when done."
5. When agent completes: post a ≤5-bullet summary to main session.

**Background / fire-and-forget mode:**
1. Collect context automatically (no questions).
2. Dispatch via Agent tool with `run_in_background: true`.
3. Reply: "Index running in background — I'll post findings when done."
4. When agent completes: post a ≤5-bullet summary.

---

# xgh:index — Codebase Indexing

## Arguments

- `path` — path to the repo directory. Defaults to current directory, or the first `github` entry for the active project in `ingest.yaml`.
- `--depth quick|full` — default: `quick`

## Stack detection

Check for these files to identify the stack:
- `Package.swift` + `.swift` files → iOS/Swift
- `build.gradle` + `.kt` files → Android/Kotlin
- `package.json` + `.ts/.tsx` files → TypeScript/React
- `go.mod` → Go
- `Cargo.toml` → Rust
- Anything else → Generic

## Quick mode (--depth quick)

Target: `--max-turns 5`, stores 10–15 memories.

1. **Directory structure**: Use `Glob` with `**/*` (depth 2) to map top-level layout
2. **Key files**: Read manifests (Package.swift, package.json, build.gradle), main entry point, README
3. **Naming conventions**: Sample 5–10 files, extract naming patterns (CamelCase types, snake_case functions, etc.)
4. **Store per area**: For each top-level module/package, extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the summary text and context-appropriate tags. Do not pass raw conversation content to lcm_store. Use tags: ["workspace", "index"]. Content to store:
   ```
   [REPO_NAME][MODULE] <module_name>: <one-sentence purpose>
   Key files: path1, path2
   Pattern: <naming/architectural pattern observed>
   ```
5. Update `index.last_full` in `ingest.yaml` for the relevant project

## Full mode (--depth full)

Target: `--max-turns 20`, stores 30–50 memories.

Everything in quick, plus:

### iOS/Swift extra passes
- Coordinator pattern: find `*Coordinator*.swift`, trace navigation hierarchy
- SPM modules: read Package.swift, map `targets:` and dependencies
- Feature flags: `Glob "**/*FeatureFlag*"` + `Grep "var.*: Bool"` to find flag declarations
- DI patterns: find `@Dependency` or `Container` usage

### Android/Kotlin extra passes
- Activity/Fragment hierarchy
- Dagger/Hilt module graph
- Navigation graph XML if present

### TypeScript/React extra passes
- Component tree (top-level routes → page components → shared components)
- State management (Redux/Zustand/Context patterns)
- Hook conventions

### All stacks
- API routes / service layer
- Test conventions (test file location, assertion patterns)
- CI/CD config (workflows, build scripts)

## Memory format

Each memory stored via `lcm_store(text, ["workspace", "index"])`:
```
[REPO] [AREA] Title: one sentence
Details: 2-3 key facts
Files: path/to/key/file.ext
Stack: <detected stack>
Indexed: <ISO date>
```

## Update project config

After completion, update `~/.xgh/ingest.yaml` for the relevant project:
```yaml
index:
  last_full: 2026-03-15T09:00:00Z
  schedule: weekly
  watch_paths:
    - "AppPackages/Sources/**"
    - "Package.swift"
```

Use python3 to safely update the YAML (read → modify → write).

## Completion output

```
✓ Indexed acme-ios (iOS/Swift) in quick mode
  15 memories stored in lossless-claude
  Modules found: Auth, Home, Passcode, Payments, Settings
  Run /xgh-index --depth full for deeper extraction
```
