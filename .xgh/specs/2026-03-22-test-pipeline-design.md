# Test Pipeline Design — config → index → architecture → test-builder

> **Goal:** Build a four-skill pipeline that analyzes any project and generates a tailored test suite. Each skill has a single responsibility and builds on the previous one's output.

## Inspiration

- [lcm E2E test strategy](https://github.com/lossless-claude/lcm/pull/2) — 19-flow TypeScript harness with mock/live mode, unified test harness, Codex-validated
- [weave E2E skill](https://github.com/PackWeave/weave/tree/main/.claude/skills/weave-e2e) — shell-based checklist runner, Claude-as-test-executor, real installations not mocks
- Codex (gpt-5.4) review feedback: rename from "e2e" to broader "test-builder", manifest as narrow IR not framework config, adaptive autonomy needs explicit confidence gates

## Pipeline Overview

```
config → index → architecture → test-builder
  │         │          │              │
  │         │          │              ├─ .xgh/test-builder/manifest.yaml (test flows)
  │         │          │              └─ .xgh/test-builder/strategy.md (human summary)
  │         │          │
  │         │          └─ xgh:architecture:* (lossless-claude memory)
  │         │             module-boundaries, dependency-graph,
  │         │             critical-paths, public-surfaces,
  │         │             integration-points, test-landscape
  │         │
  │         └─ xgh:index:* (lossless-claude memory)
  │            module inventory, key files, naming patterns
  │
  └─ ~/.xgh/ingest.yaml (global, multi-project)
     stack, surfaces, project config
```

**Project resolution:** `ingest.yaml` is a global multi-project manifest at `~/.xgh/ingest.yaml`. Skills resolve the active project by matching the current working directory's git remote against `projects.<name>.github` entries. If no match → stop and prompt user to run `/xgh:config add-project`.

### Single Responsibilities

| Skill | Responsibility |
|-------|---------------|
| `/xgh:config` | Read/write `ingest.yaml` — source of truth for project identity |
| `/xgh:index` | Raw inventory of what exists in the codebase |
| `/xgh:architecture` | How the pieces connect and where the boundaries are |
| `/xgh:test-builder` | What to validate and how |

### Freshness Chain

| Artifact | Written by | Read by | Staleness warning | Hard refusal |
|----------|-----------|---------|-------------------|-------------|
| `ingest.yaml` (stack/surfaces) | config | index, architecture | — | Missing → stop |
| `xgh:index:*` memories | index | architecture | >14 days | >60 days |
| `xgh:architecture:*` memories | architecture | test-builder | >7 days | >30 days |
| `.xgh/test-builder/manifest.yaml` | test-builder init | test-builder run | — | Missing → run init |

### Scheduling

| Skill | Suggested cadence |
|-------|------------------|
| config | Manual only (no scheduling) |
| index | Weekly or on significant git changes |
| architecture | Daily or post-index |
| test-builder run | On-demand or CI-triggered |

### Freshness Implementation

Freshness timestamps are stored in `~/.xgh/ingest.yaml` under the project's config, not parsed from memory body text:

```yaml
projects:
  xgh:
    index:
      last_run: 2026-03-22T15:00:00Z
    architecture:
      last_run: 2026-03-22T16:00:00Z
      mode: quick  # or full
```

Downstream skills read these timestamps to evaluate staleness. This avoids parsing dates from unstructured memory content.

---

## Skill 1: `/xgh:config`

**Purpose:** Structured read/write interface for `~/.xgh/ingest.yaml`. Replaces ad-hoc python one-liners scattered across skills.

### Subcommands

| Command | What it does |
|---------|-------------|
| `config show [section]` | Pretty-print the manifest (or a section: `show projects`, `show budget`) |
| `config set <path> <value>` | Set a value using dot-path: `config set projects.xgh.stack shell` |
| `config add-project <name>` | Interactive — asks minimal questions, adds a project entry |
| `config remove-project <name>` | Removes a project entry (with confirmation) |
| `config validate` | Checks manifest against schema — reports missing fields, type mismatches |

### New Project Schema Fields

```yaml
projects:
  xgh:
    stack: shell              # declared, not guessed from filesystem
    surfaces:                 # what the project exposes
      - type: cli
      - type: plugin
    github:
      - tokyo-megacorp/xgh
    # ... existing fields unchanged
```

**`stack`** — language/framework declaration. Read by index and downstream skills instead of guessing from filesystem markers.

**`surfaces`** — what the project exposes to users. Key input for test-builder's strategy selection. Types: `cli`, `api`, `web`, `mobile`, `library`, `plugin`, `sdk`.

### Out of Scope (follow-ups)

- Schema version migrations
- Bulk operations
- Import/export

---

## Skill 2: `/xgh:index` (refactored)

**Purpose:** Raw codebase inventory. Scans a repository to extract module list, key files, and naming conventions into lossless-claude memory. Reads project config from `ingest.yaml`.

### What It Does

1. **Read project config** — pulls `stack` and `surfaces` from `ingest.yaml`. If missing → stop, tell user to run `/xgh:config set` first.
2. **Directory structure** — Glob depth 2, map top-level layout
3. **Key files** — read manifests, entry points, README
4. **Module inventory** — list modules, key files per module
5. **Naming conventions** — sample files, extract patterns
6. **Store to memory** — write raw inventory to lossless-claude with `xgh:index:` tags
7. **Update timestamps** — write `index.last_run` in `ingest.yaml`
8. **Offer architecture** — "Index complete. Run `/xgh:architecture`?"

### What's Removed (vs current)

- Execution mode preamble (P1-P4, 60 lines of preference management)
- Stack detection from filesystem (now read from `ingest.yaml`)
- All "full mode" extra passes (moved to architecture)
- MCP dependency guard check (doctor's job)
- Quick/full mode distinction (index is always fast, ~2 min)

### Memory Format

```
[REPO][MODULE] <module_name>: <one-sentence purpose>
Key files: path1, path2
Pattern: <naming pattern observed>
Stack: <from ingest.yaml>
Indexed: <ISO date>
```

Tags: `["xgh:index", "<repo-name>"]`

---

## Skill 3: `/xgh:architecture` (new)

**Purpose:** Higher-level architectural analysis. Reads index inventory, produces structured definitions of how modules connect, where boundaries are, and what the critical paths are.

### Trigger

`/xgh:architecture [mode]` where mode is `quick` (default) or `full`

### Hard Prerequisite

`/xgh:index` must have run. Checks for `xgh:index:*` entries in lossless-claude memory. If missing → stop, tell user to run `/xgh:index` first.

### Artifacts Produced

Written to lossless-claude memory with `xgh:architecture:` prefix:

| Artifact | Description |
|----------|-------------|
| `module-boundaries` | Which modules exist, what each owns, where the seams are |
| `dependency-graph` | How modules depend on each other (internal + external) |
| `critical-paths` | Key user/data journeys through the system |
| `public-surfaces` | Unified view: CLI commands, API endpoints, UI routes, exported functions, SDK methods |
| `integration-points` | External systems: databases, APIs, queues, file systems |
| `test-landscape` | Existing test coverage — what's tested, what frameworks are in use, gaps |

### Quick vs Full

- **Quick** (~2-3 min) — module boundaries, public surfaces, integration points.
- **Full** (~10-15 min) — everything above plus dependency graph, critical paths, deep test landscape.

**Artifact availability by mode:**

| Artifact | Quick | Full |
|----------|-------|------|
| module-boundaries | yes | yes |
| public-surfaces | yes | yes |
| integration-points | yes | yes |
| dependency-graph | — | yes |
| critical-paths | — | yes |
| test-landscape | — | yes |

**Test-builder requirements:** test-builder `init` requires at minimum: module-boundaries, public-surfaces, integration-points (all available from quick). If test-builder detects complex surfaces or the complexity gate fires, it will recommend running `/xgh:architecture full` and tell the user which additional artifacts would improve test generation.

### Stack-Specific Analysis (moved from index)

- **iOS/Swift:** Coordinator pattern, SPM modules, feature flags, DI patterns
- **Android/Kotlin:** Activity/Fragment hierarchy, Dagger/Hilt module graph, navigation graph
- **TypeScript/React:** Component tree, state management, hook conventions
- **All stacks:** API routes, service layer, CI/CD config

### Schedulable

Can be added to `/xgh:schedule`. Suggested: daily or post-index. Timestamps each artifact for freshness checking.

---

## Skill 4: `/xgh:test-builder` (new)

**Purpose:** Analyze architectural definitions and generate a tailored test suite. Two phases: init (generate) and run (execute).

### Hard Prerequisite

`xgh:architecture:*` entries must exist in lossless-claude memory. Freshness check: warns if >7 days old, refuses if >30 days.

### Phase 1: Init

`/xgh:test-builder init`

**Step 1 — Read architectural definitions:** Pulls module boundaries, critical paths, public surfaces, integration points, test landscape from memory.

**Step 2 — Determine project surface type:**

| Surface detected | Test strategy |
|-----------------|---------------|
| CLI commands | Acceptance — run commands, assert stdout/exit codes |
| API endpoints | Contract + integration — HTTP calls, response validation |
| Web UI routes | E2E — browser-based flows (Playwright/Cypress) |
| Mobile app screens | E2E — device/simulator flows |
| Library/SDK exports | Contract — public API assertions, consumer scenarios |
| Mixed surfaces | Layered — generates multiple strategy types |

**Step 3 — Complexity gate (adaptive autonomy):**

Explicit triggers for interview mode:
- Multiple surfaces detected
- No clear entry point
- Auth/stateful setup required
- External dependencies that may need mocking
- Test landscape shows <30% coverage in critical paths

If none fire → autonomous generation. Otherwise → interview developer on: critical journeys, what breaks vs what's stable, external deps to mock vs hit live, deployment target.

**Step 4 — Generate manifest** (`.xgh/test-builder/manifest.yaml`):

Manifest is written atomically: generated to a temp file first, validated, then moved into place. If init fails mid-generation (interview abandoned, MCP unreachable), no partial manifest is left behind. `run` validates the manifest on load and refuses to execute if it contains unresolved placeholders or schema errors.

```yaml
version: 1
project: acme-api
generated: 2026-03-22T16:00:00Z
architecture_ref: 2026-03-22T15:00:00Z

surfaces:
  - type: api
    entry: ./src/server.ts
    base_url: http://localhost:3000

strategies:
  - name: contract
    executor: shell

flows:
  - name: health-check
    surface: api
    strategy: contract
    goal: "Verify service starts and responds"
    prerequisites:
      - run: "npm start &"
        wait_for: "localhost:3000/health"
    steps:
      - run: "curl -s localhost:3000/health"
        assert:
          status: 200
          body_contains: '"status":"ok"'
    cleanup:
      - run: "kill %1"

  - name: user-registration
    surface: api
    strategy: contract
    goal: "Create user, verify response, attempt duplicate"
    steps:
      - run: "curl -s -X POST localhost:3000/users -d '{...}'"
        assert:
          status: 201
      - run: "curl -s -X POST localhost:3000/users -d '{...}'"
        assert:
          status: 409
```

**Manifest schema covers:** project surface, prerequisites/env, flows/scenarios, step executor kind, assertions, evidence/artifacts, and projection targets. Nothing more — it describes *what to test*, not *how the framework runs it*.

### Executor Kinds

| Executor | What it does | Prerequisites |
|----------|-------------|---------------|
| `shell` | Runs a command, captures stdout/stderr/exit code | None (default) |
| `http` | Makes HTTP requests via curl, asserts status/headers/body | Target service running |
| `browser` | Delegates to Playwright/Cypress (must be installed in project) | `npx playwright` or `npx cypress` available |
| `mobile` | Delegates to XCTest/Espresso or AXe simulator automation | Xcode/Android Studio, simulator running |
| `library` | Imports and calls exported functions, asserts return values | Project's native test runner (vitest, pytest, etc.) |
| `custom` | Runs a user-provided script, asserts exit code 0 = pass | Script exists at declared path |

Each executor is a thin dispatch layer. The manifest says "run this step with executor X". The skill maps that to the appropriate tool call. If the required tool isn't available, the step is marked `skipped` with an explanation.

### Assertion Types

| Assertion | Applies to | Example |
|-----------|-----------|---------|
| `exit_code` | shell, custom | `exit_code: 0` |
| `stdout_contains` | shell, custom | `stdout_contains: "OK"` |
| `stdout_matches` | shell, custom | `stdout_matches: "v\\d+\\.\\d+"` |
| `status` | http | `status: 200` |
| `body_contains` | http | `body_contains: '"status":"ok"'` |
| `body_json_path` | http | `body_json_path: { path: "$.data.id", exists: true }` |
| `header_contains` | http | `header_contains: { key: "content-type", value: "json" }` |
| `file_exists` | any | `file_exists: "./output/report.html"` |
| `returns` | library | `returns: { type: "object", has_key: "id" }` |

**Step 5 — Optional native scaffold:** For known ecosystems, generates test files that implement manifest flows. Manifest remains source of truth.

**Step 6 — Generate `strategy.md`:** Human-readable companion derived from manifest — documents what's being tested and why.

### Phase 2: Run

`/xgh:test-builder run [flow]`

Reads manifest, executes flows (all or targeted by name). Fails fast if manifest has unresolved questions or missing prerequisites.

**Output:**

```
## 🧪 test-builder run

| Flow | Surface | Steps | Result | Notes |
|------|---------|-------|--------|-------|
| health-check | api | 1/1 | ✅ | 200ms |
| user-registration | api | 2/2 | ✅ | |
| duplicate-guard | api | 1/1 | ❌ | Expected 409, got 500 |

3 flows · 4/5 steps passed · 1 failure
```

---

## Implementation Notes

### Dogfooding Plan

Test the pipeline on two projects simultaneously:
1. **xgh itself** (shell plugin) — CLI commands, skill triggering, config validation
2. **lcm** (TypeScript daemon) — API routes, memory operations, hook lifecycle

This validates both the shell-based and framework-native paths.

### GitHub Issues for Follow-ups

- `/xgh:config` schema migrations and bulk operations
- `/xgh:index` execution mode as shared preamble pattern
- `/xgh:architecture` scheduler integration
- `/xgh:test-builder` CI integration (GitHub Actions workflow generation)
- Codex skill dispatch improvement ([#32](https://github.com/tokyo-megacorp/xgh/issues/32))
