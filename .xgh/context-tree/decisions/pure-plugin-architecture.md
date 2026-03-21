---
title: "Pure Plugin Architecture — Source Repo IS the Plugin"
type: decision
status: validated
importance: 90
tags: [decision, architecture, plugin, install, claude-code, refactor]
keywords: [plugin, install.sh, claude-plugin, marketplace, xgh-init]
created: 2026-03-20
updated: 2026-03-20
---

## Raw Concept

xgh was refactored from a "project-per-install" model to a **pure Claude Code plugin** where the source repository itself is the plugin package.

**Before (legacy):**
- `install.sh` copied skills/commands/hooks into per-project `.claude/` directories
- Each project needed its own copy of xgh files
- Skills lived in `.claude/skills/xgh-*/` and commands in `.claude/commands/xgh-*/`

**After (current):**
- Install once globally: `claude plugin install xgh@ipedro`
- Skills load from `~/.claude/plugins/cache/ipedro/xgh/`
- No per-project file copies
- `plugin.json` is at repo root (`.claude-plugin/plugin.json`)
- `/xgh-init` (not install.sh) handles first-run setup
- Source repo layout: `skills/`, `commands/`, `agents/`, `config/`, `hooks/`, `templates/`

**Key files:**
- `.claude-plugin/plugin.json` — plugin manifest (name, version, author, keywords)
- `.claude-plugin/marketplace.json` — marketplace listing
- `skills/init/init.md` — first-run onboarding (replaces install.sh)
- `templates/xgh-instructions.md` — copied to `.xgh/xgh.md` at init time

## Narrative

The original xgh required running `install.sh` which copied files into each project's `.claude/` directory. This caused issues: stale copies, version drift between projects, and cleanup complexity when updating.

The refactor made the source repo the canonical plugin package. Claude Code's plugin system handles installation, versioning, and loading from a central cache. Users install once and all projects benefit. `/xgh-init` replaces `install.sh` for first-run setup (creates `~/.xgh/` data dirs, copies static instructions, configures MCP).

**Stale install detection**: `/xgh-init` checks for legacy `xgh-*` entries in `.claude/skills/` and `.claude/commands/` and removes them automatically.

## Facts

- **Install command**: `claude plugin install xgh@ipedro` (one-time, global)
- **Plugin cache**: `~/.claude/plugins/cache/ipedro/xgh/<version>/`
- **No install.sh**: removed in commit `9a4dfae`; `/xgh-init` is the new entry point
- **Plugin manifest**: `.claude-plugin/plugin.json` at repo root
- **Legacy cleanup**: `/xgh-init` removes stale `.claude/skills/xgh-*` and `.claude/commands/xgh-*`
- **Static instructions**: `templates/xgh-instructions.md` → copied to `.xgh/xgh.md` → referenced as `@.xgh/xgh.md` in `CLAUDE.local.md`
- **Commit refs**: `7e20169` (flatten to root), `9a4dfae` (remove install.sh), `34d53fb` (pure plugin)
