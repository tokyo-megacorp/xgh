# xgh Claude Plugin — Design Spec

**Date:** 2026-03-16
**Status:** Approved
**Goal:** Restructure xgh as a Claude plugin and publish to a self-hosted GitHub registry (`github:ipedro/xgh`), with a path to the official `anthropics/claude-plugins-official` registry later.

---

## Context

xgh currently distributes as a bash installer that copies skills, hooks, and MCP config into per-project `.claude/` directories. Claude plugins are user-level bundles (`~/.claude/plugins/`) that provide skills and hooks without per-project file copies. This spec defines how to migrate xgh to the plugin model while preserving its per-project memory features.

---

## Approach: Plugin-native architecture (clean infra/plugin split)

`install.sh` handles infrastructure (Qdrant, inference backend, Node/Python deps) and registers the plugin. The plugin itself (`plugin/`) is the canonical distribution artifact for skills and hooks. Both paths end with the same plugin installed at `~/.claude/plugins/`.

---

## Section 1: Plugin Structure

```
xgh/
├── plugin/                     # canonical plugin artifact
│   ├── plugin.md               # manifest: name, version, description, author
│   ├── skills/                 # moved from skills/ — user-level, never per-project
│   │   ├── xgh-help/
│   │   ├── xgh-init/
│   │   ├── xgh-brief/
│   │   ├── xgh-ask/
│   │   ├── xgh-curate/
│   │   ├── xgh-collab/
│   │   ├── xgh-design/
│   │   ├── xgh-implement/
│   │   ├── xgh-investigate/
│   │   ├── xgh-profile/
│   │   ├── xgh-retrieve/
│   │   ├── xgh-analyze/
│   │   ├── xgh-track/
│   │   ├── xgh-doctor/
│   │   ├── xgh-index/
│   │   ├── xgh-calibrate/
│   │   ├── xgh-status/
│   │   ├── xgh-setup/
│   │   └── xgh-todo-killer/
│   └── hooks/                  # moved from hooks/
│       ├── session-start.sh
│       └── prompt-submit.sh
├── install.sh                  # infra only + plugin registration
├── uninstall.sh                # gains plugin deregistration
├── techpack.yaml               # updated to reference plugin/ paths
├── config/                     # unchanged
├── lib/                        # unchanged
├── templates/                  # CLAUDE.local.md template (used by /xgh-init)
├── tests/                      # unchanged
└── docs/                       # unchanged
```

`plugin.md` declares name, version, description, author, and points to `skills/` and `hooks/` subdirectories.

---

## Section 2: Install Paths

### Full install (new users, infra not yet running)

```bash
curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/install.sh | bash
```

Steps:
1. Platform detection → install Qdrant, vllm-mlx / Ollama / remote backend, Node/Python deps
2. Download/cache `plugin/` to `~/.claude/plugins/cache/xgh/<version>/`
3. Write registration to `~/.claude/plugins/installed_plugins.json`
4. Skills available in all Claude Code sessions immediately

### Lite install (infra already running)

```
/plugin install github:ipedro/xgh
```

Fetches `plugin/` from GitHub, caches it, registers it. No infra touched. Same end state as full install.

### Per-project activation (either path)

```
/xgh-init
```

Run once inside a repo. See Section 3.

---

## Section 3: `/xgh-init` — Per-Project Activation

### Dependency check (runs first)

Checks three things in order:

| Dependency | Check | Response |
|---|---|---|
| Cipher MCP | `@byterover/cipher` reachable | Auto-fix: register in MCP config if missing |
| Qdrant | `QDRANT_URL` responding | Guide: print install instructions or suggest `XGH_BACKEND=remote` |
| Inference backend | vllm-mlx / Ollama / remote URL responding | Guide: print install instructions |

**Tiers of response:**
- **Can auto-fix** → fix silently, report what was done
- **Can guide** → print clear instructions: _"Run `install.sh` to install Qdrant and the inference backend, or set `XGH_BACKEND=remote` and `XGH_REMOTE_URL=<url>` to use an existing endpoint"_
- **Partial mode** (all checks fail) → scaffold project files anyway, tell Claude: _"xgh memory tools are not yet configured. Run `install.sh` or `/plugin install github:ipedro/xgh` to complete setup. Context tree is available but Cipher search will not work until backends are running."_

`/xgh-init` never hard-fails — it always makes progress and leaves a clear next step.

### Scaffolding (after dependency check)

Creates per-project files (git-committed, team-shareable):
- `.xgh/context-tree/` — structured knowledge base
- `CLAUDE.local.md` — team-specific agent instructions (filled from template)
- `.xgh/config` — sets `CIPHER_COLLECTION` to project name

Skills are **not** copied into the project. They remain in `~/.claude/plugins/cache/xgh/`.

---

## Section 4: Migration (What Changes)

### Files moving
- `skills/*` → `plugin/skills/`
- `hooks/*` → `plugin/hooks/`

### New files
- `plugin/plugin.md`
- Plugin registration logic appended to `install.sh`

### Files shrinking
- `install.sh` — drops all skill-copying logic; keeps infra setup + adds plugin registration
- `techpack.yaml` — skills/hooks sections reference `plugin/` paths

### Files unchanged
- `config/`, `lib/`, `templates/`, `tests/`, `docs/`

### Uninstall
- `uninstall.sh` gains logic to deregister from `~/.claude/plugins/installed_plugins.json`
- `/xgh-init` detects and removes stale `.claude/skills/xgh-*` entries from old installs

### No breaking changes to skills
Skill markdown files move but content is unchanged. All slash commands (`/xgh-help`, `/xgh-init`, etc.) work identically after migration.

---

## Distribution Strategy

1. **Now:** Self-hosted at `github:ipedro/xgh` — installable via `/plugin install github:ipedro/xgh` or `install.sh`
2. **Later:** Submit to `anthropics/claude-plugins-official` once format is stable and plugin is battle-tested

---

## Out of Scope

- npm package / monorepo output artifacts
- Docker Compose distribution
- Changes to skill content or behavior
- Changing the Cipher/Qdrant infrastructure itself
