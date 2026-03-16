# xgh Claude Plugin — Design Spec

**Date:** 2026-03-16
**Status:** Approved
**Goal:** Restructure xgh as a Claude plugin and publish to a self-hosted GitHub registry (`github:ipedro/xgh`).

---

## Context

xgh currently distributes as a bash installer that copies skills, hooks, and MCP config into per-project `.claude/` directories. Claude plugins install to `~/.claude/plugins/` at user level and provide skills/commands/hooks without per-project file copies. This spec defines how to migrate xgh to the plugin model while preserving its per-project memory features.

---

## Approach: Plugin-native architecture (clean infra/plugin split)

`install.sh` handles infrastructure (Qdrant, inference backend, Node/Python deps) and registers the plugin. The plugin itself (`plugin/`) is the canonical distribution artifact. Both install paths end with the plugin registered at `~/.claude/plugins/`.

---

## Section 1: Plugin Structure

The repo gains a `plugin/` directory mirroring the structure of established plugins (e.g., superpowers). Both `commands/` and `skills/` move inside it.

```
xgh/
├── plugin/                     # canonical plugin artifact
│   ├── README.md               # informational; not required by Claude
│   ├── gemini-extension.json   # cross-platform manifest (name, version, description)
│   ├── commands/               # moved from commands/ — slash command trigger files
│   │   ├── analyze.md
│   │   ├── ask.md
│   │   ├── brief.md
│   │   ├── briefing.md
│   │   ├── calibrate.md
│   │   ├── collab.md
│   │   ├── curate.md
│   │   ├── design.md
│   │   ├── doctor.md
│   │   ├── help.md
│   │   ├── implement.md
│   │   ├── index.md
│   │   ├── init.md
│   │   ├── investigate.md
│   │   ├── profile.md
│   │   ├── retrieve.md
│   │   ├── setup.md
│   │   ├── status.md
│   │   ├── todo-killer.md
│   │   ├── track.md
│   │   └── xgh-collaborate.md
│   ├── skills/                 # moved from skills/ — workflow content
│   │   ├── analyze/
│   │   ├── ask/
│   │   ├── briefing/
│   │   ├── calibrate/
│   │   ├── collab/
│   │   ├── curate/
│   │   ├── design/
│   │   ├── doctor/
│   │   ├── implement/
│   │   ├── index/
│   │   ├── init/
│   │   ├── investigate/
│   │   ├── knowledge-handoff/
│   │   ├── mcp-setup/
│   │   ├── pr-context-bridge/
│   │   ├── profile/
│   │   ├── retrieve/
│   │   ├── team/
│   │   │   ├── cross-team-pollinator/
│   │   │   ├── onboarding-accelerator/
│   │   │   └── subagent-pair-programming/
│   │   ├── todo-killer/
│   │   └── track/
│   └── hooks/                  # moved from hooks/
│       ├── session-start.sh
│       └── prompt-submit.sh
├── install.sh                  # infra only + plugin registration
├── uninstall.sh                # gains plugin deregistration
├── techpack.yaml               # retained for install.sh reference; skills/hooks paths updated
├── config/                     # unchanged
├── lib/                        # unchanged
├── templates/                  # CLAUDE.local.md template (used by /xgh-init)
├── tests/                      # updated to cover plugin structure
└── docs/                       # unchanged
```

**Note on `commands/` vs `skills/`:** `commands/` contains the slash command trigger files (thin wrappers that invoke skills). `skills/` contains the actual workflow content. Both are required and distinct — this mirrors the superpowers plugin structure exactly.

### Plugin registration format

`install.sh` writes to `~/.claude/plugins/installed_plugins.json`:

```json
"xgh@ipedro": [
  {
    "scope": "user",
    "installPath": "/Users/<user>/.claude/plugins/cache/ipedro/xgh/<version>",
    "version": "1.0.0",
    "installedAt": "<ISO8601>",
    "lastUpdated": "<ISO8601>",
    "gitCommitSha": "<sha>"
  }
]
```

Registry key format: `{plugin-name}@{registry-name}` (e.g., `xgh@ipedro`).
Install path: `~/.claude/plugins/cache/{registry}/{plugin}/{version}/`.

### `gemini-extension.json` format

```json
{
  "name": "xgh",
  "description": "Persistent memory and team context for AI-assisted development",
  "version": "1.0.0"
}
```

---

## Section 2: Install Paths

### Full install (new users, infra not yet running)

```bash
curl -fsSL https://raw.githubusercontent.com/ipedro/xgh/main/install.sh | bash
```

Steps:
1. Platform detection → install Qdrant, vllm-mlx / Ollama / remote backend, Node/Python deps
2. Download/cache `plugin/` to `~/.claude/plugins/cache/ipedro/xgh/<version>/`
3. Write registration to `~/.claude/plugins/installed_plugins.json`
4. Skills and commands available in all Claude Code sessions immediately

**Upgrade detection:** If a prior installation is found (old-style per-project skill copies in `.claude/skills/`), `install.sh` prints a migration notice and skips re-installing infra components already present.

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

| Dependency | Check | Response tier |
|---|---|---|
| Cipher MCP | `@byterover/cipher` reachable | Auto-fix: register in MCP config if missing |
| Qdrant | `QDRANT_URL` responding | Guide: print install instructions or suggest `XGH_BACKEND=remote` |
| Inference backend | vllm-mlx / Ollama / remote URL responding | Guide: print install instructions |

**Response tiers:**
- **Can auto-fix** → fix silently, report what was done
- **Can guide** → clear instructions: _"Run `install.sh` to install Qdrant and the inference backend, or set `XGH_BACKEND=remote` and `XGH_REMOTE_URL=<url>` to use an existing endpoint"_
- **Partial mode** (all checks fail) → scaffold anyway, tell Claude: _"xgh memory tools are not yet configured. Run `install.sh` or `/plugin install github:ipedro/xgh` to complete setup. Context tree is available but Cipher search will not work until backends are running."_

`/xgh-init` never hard-fails — it always makes progress and leaves a clear next step.

### Stale install cleanup

If `/xgh-init` detects old-style per-project skill copies (`.claude/skills/xgh-*`), it removes them and prints: _"Removed legacy per-project skill copies — skills now load from the user-level plugin."_

### Scaffolding (after dependency check)

Creates per-project files (git-committed, team-shareable):
- `.xgh/context-tree/` — structured knowledge base
- `CLAUDE.local.md` — team-specific agent instructions (filled from template)
- `.xgh/config` — sets `CIPHER_COLLECTION` to project name

Skills and commands are **not** copied into the project.

---

## Section 4: Migration (What Changes)

### Files moving
- `commands/*` → `plugin/commands/`
- `skills/*` → `plugin/skills/` (including `skills/team/` subtree)
- `hooks/*` → `plugin/hooks/`

### New files
- `plugin/README.md`
- `plugin/gemini-extension.json`
- Plugin registration + upgrade detection logic in `install.sh`

### Files shrinking
- `install.sh` — drops all skill/command-copying logic; keeps infra setup; adds plugin registration
- `techpack.yaml` — skills/hooks/commands paths updated to reference `plugin/`; role clarified as install.sh reference, not the plugin manifest

### Files unchanged
- `config/`, `lib/`, `templates/`, `docs/`

### Uninstall
- `uninstall.sh` removes the `xgh@ipedro` entry from `~/.claude/plugins/installed_plugins.json` and deletes the cached plugin directory

### No breaking changes to skill content
Skill and command markdown files move but their content is unchanged. All slash commands work identically after migration.

### Tests
Existing tests (`test-install.sh`, `test-config.sh`, `test-techpack.sh`, `test-uninstall.sh`) updated to:
- Assert `plugin/commands/` and `plugin/skills/` exist and are complete
- Assert plugin registration appears correctly in `installed_plugins.json`
- Assert no skill copies appear in per-project `.claude/skills/` after install
- Assert `/xgh-init` dependency check output for each failure tier

---

## Out of Scope

- npm package or Docker Compose distribution outputs
- Changes to skill/command content or behavior
- Changes to Cipher/Qdrant infrastructure
- Submission to `anthropics/claude-plugins-official` (future, separate effort)
