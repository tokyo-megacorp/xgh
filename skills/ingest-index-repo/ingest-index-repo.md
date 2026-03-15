---
name: xgh:ingest-index-repo
description: >
  Codebase architecture extraction. Scans a repository to extract modules, patterns,
  navigation flows, naming conventions, and feature flags into Cipher memory.
  Supports quick (~5 min) and full (~30 min) modes.
type: flexible
triggers:
  - when the user runs /xgh-index-repo
  - when the user says "index repo", "index codebase", "scan the codebase"
  - when invoked by ingest-track after adding a GitHub repo
mcp_dependencies:
  - mcp__cipher__cipher_extract_and_operate_memory
  - mcp__cipher__cipher_memory_search
---

# xgh:ingest-index-repo — Codebase Indexing

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
4. **Store per area**: For each top-level module/package, call `cipher_extract_and_operate_memory` with:
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

Each memory stored via `cipher_extract_and_operate_memory`:
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
  15 memories stored in Cipher
  Modules found: Auth, Home, Passcode, Payments, Settings
  Run /xgh-index-repo --depth full for deeper extraction
```
