---
title: Known Gotchas & Issues
type: constraint
status: validated
importance: 85
tags: [gotcha, bug, constraint, mcp-config, plugin, deduplication, installer]
keywords: [gotcha, known-issue, mcp-json, plugin-duplication, skills-dedup]
created: 2026-03-18
updated: 2026-03-18
---

# Known Gotchas & Issues

## Raw Concept

### 1. MCP config file path — project level

- ✅ Correct: `.claude/.mcp.json` (hidden dot-prefix on filename)
- ❌ Wrong: `.claude/mcp.json` (silently ignored by Claude Code)
- User-level config (different): `~/.claude/mcp.json` (no dot on mcp.json)

### 2. Plugin skill duplication (commands/ vs skills/)

- The xgh plugin has both `commands/*.md` (slash commands, loaded as `xgh-*`) and `skills/*` (loaded as `xgh:*`)
- Claude Code loads both directories as skills, causing duplicates
- Machine fix (applied 2026-03-17): deleted `~/.claude/plugins/cache/extreme-go-horse/xgh/1.0.0/commands/`

### 3. Installer superpowers dedup bug

- `install_plugin()` in `install.sh` doesn't check if superpowers is already installed from another marketplace before calling `claude plugin install`
- Can result in two versions of superpowers co-existing (`superpowers@claude-plugins-official` and `superpowers@superpowers-marketplace`)
- Fix needed: dedup check against `installed_plugins.json` before install

## Narrative

**MCP config path:** This mistake is easy to make when "standardizing" or moving config files. Claude Code specifically requires the dot-prefix on `.mcp.json` for project-level config, while user-level config uses a different convention. The file is silently ignored without error if named wrong — hard to debug.

**Skill duplication:** During xgh's evolution from slash-commands-only to skills+commands hybrid, both directories accumulated overlapping content. The `commands/` directory serves slash commands (user-facing `/xgh-*`), while `skills/` serves skill invocations (`xgh:*`). Claude Code treats both as loadable "skills," causing the same functionality to appear twice. Long-term fix: consolidate — commands for user-facing slash commands, skills for agent-invoked workflows.

**Installer dedup:** When a user already has superpowers installed from one marketplace and xgh tries to install from another, both end up active. Symptoms: two identical sets of superpowers skills with different prefixes.

## Facts

- **Gotcha:** `.claude/.mcp.json` is correct for project MCP config; `.claude/mcp.json` is silently ignored
- **Gotcha:** xgh plugin loads skills from both `commands/` and `skills/`, causing `xgh-*` and `xgh:*` duplicates
- **Bug:** `install_plugin()` lacks dedup check for superpowers already installed from a different marketplace
- **Workaround:** Delete `~/.claude/plugins/cache/extreme-go-horse/xgh/1.0.0/commands/` to remove `xgh-*` duplicates
- **Constraint:** User-level MCP config (`~/.claude/mcp.json`) uses different naming convention than project-level
