# Spec: /xgh-help Command, Command Rename, and Output Refresh

**Date:** 2026-03-15
**Status:** Draft
**Scope:** New help command, rename 18 commands to two tiers, output style guide, init flow update

---

## 1. Problem

- No help/onboarding command — new users don't know what's available
- 18 commands with inconsistent naming (`ingest-*` prefix on user-facing commands, verbose names)
- Command output is plain-text monospace — doesn't use Claude Code's markdown rendering
- `/xgh-init` doesn't include knowledge curation step
- Duplicate command (`xgh-collaborate` and `xgh-xgh-collaborate`)

## 2. Changes

### 2.1 Command Rename

**Everyday commands** (what users run):

| Old Name | New Name | Notes |
|----------|----------|-------|
| `briefing` | `brief` | Shorter verb |
| `implement-design` | `design` | "Implement from design" is implied |
| `query` | `ask` | More natural — "ask your memory" |
| `collaborate` | `collab` | Shorter |
| `team-profile` | `profile` | Shorter |
| `init` | `init` | Keep |
| `setup` | `setup` | Keep |
| `status` | `status` | Keep |
| `investigate` | `investigate` | Keep |
| `implement` | `implement` | Keep |
| `curate` | `curate` | Keep |
| — | `help` | **New** |

**Admin commands** (run occasionally or by scheduler):

| Old Name | New Name | Notes |
|----------|----------|-------|
| `ingest-track` | `track` | Drop `ingest-` prefix |
| `ingest-doctor` | `doctor` | Drop prefix |
| `ingest-retrieve` | `retrieve` | Drop prefix |
| `ingest-analyze` | `analyze` | Drop prefix |
| `ingest-index-repo` | `index` | Much shorter |
| `ingest-calibrate` | `calibrate` | Drop prefix |

**Removed:**

| Command | Reason |
|---------|--------|
| `xgh-collaborate` | Duplicate of `collaborate`/`collab` |

**Rename strategy:**
- Rename files in `commands/` and skill directories in `skills/`.
- When renaming a skill directory, also rename the internal markdown file to match (e.g., `skills/briefing/briefing.md` → `skills/brief/brief.md`). Convention: "markdown file matches directory name."
- The installer uses glob patterns (`"${PACK_DIR}/skills/"*/` and `"${PACK_DIR}/commands/"*.md`), so renaming source files is sufficient — no hardcoded name lists to update.
- Update all `id`, `source`, and `description` fields in `techpack.yaml` to reflect new names.

### 2.2 Output Style Guide

All `/xgh-*` command markdown files must instruct Claude to format output following these rules:

1. **Header:** Always start with `## 🐴🤖 xgh <command>`
2. **Subtitle:** One-line summary of what happened, below the header
3. **Tables:** Use markdown tables for all structured data — never monospace alignment or indented key-value pairs
4. **Status indicators:** Use ✅ ⚠️ ❌ in table cells for pass/warn/fail
5. **Sections:** Use `###` for subsections
6. **Bold:** Bold key numbers and names in table cells
7. **Next step:** End with an italicized suggestion when relevant
8. **No dividers:** No `== xgh Status ==`, `---`, or `====` text dividers
9. **Scannable:** No walls of text — tables and short sentences

**Template:**

```markdown
## 🐴🤖 xgh <command>

<one-liner>

| Key | Value |
|-----|-------|
| ... | ...   |

### <section>

| ... | ... |

*Next step: ...*
```

### 2.3 /xgh-help Command

A new command file `commands/help.md` that produces a contextual + static guide.

**Contextual section** (checks state, then recommends):
1. Check if init has been run (look for `~/.xgh/ingest.yaml` — installed globally by `install.sh`)
2. Check if any projects are tracked (projects in `~/.xgh/ingest.yaml`)
3. Check if codebase is indexed (search Cipher for repo architecture memories)
4. Check if briefing has been run recently (search Cipher for recent briefing memories)
5. Based on gaps, suggest the next step

**Static section** (always shown):
Two-tier command reference — everyday and admin — with one-liner descriptions and suggested workflows.

**Example output:**

```markdown
## 🐴🤖 xgh help

### What to do next

You've completed init and indexed the codebase, but haven't tracked any projects yet.

| Step | Command | Why |
|------|---------|-----|
| 1 | `/xgh-track` | Add a project (Slack channels, Jira, GitHub) |
| 2 | `/xgh-brief` | Get a session briefing |

### Everyday Commands

| Command | What it does |
|---------|-------------|
| `/xgh-brief` | Morning briefing — Slack, Jira, GitHub summary |
| `/xgh-status` | Memory stats and context tree health |
| `/xgh-ask` | Search your memory with natural language |
| `/xgh-investigate` | Debug from a Slack thread or bug report |
| `/xgh-implement` | Implement a ticket with full context |
| `/xgh-design` | Implement a UI from a Figma design |
| `/xgh-collab` | Coordinate with other AI agents |
| `/xgh-curate` | Store knowledge in memory + context tree |
| `/xgh-profile` | Analyze an engineer's Jira throughput |

### Setup & Admin

| Command | What it does |
|---------|-------------|
| `/xgh-init` | First-run onboarding |
| `/xgh-setup` | Audit and configure MCP integrations |
| `/xgh-track` | Add a project to context monitoring |
| `/xgh-index` | Index a codebase into memory |
| `/xgh-doctor` | Validate pipeline health |
| `/xgh-calibrate` | Tune dedup similarity threshold |
| `/xgh-retrieve` | Run retrieval loop (usually automated) |
| `/xgh-analyze` | Run analysis loop (usually automated) |

### Suggested Workflows

**Starting a new session:**
`/xgh-brief` → see what needs attention → `/xgh-implement` or `/xgh-investigate`

**Onboarding to a project:**
`/xgh-track` → `/xgh-index` → `/xgh-brief`

**After completing significant work:**
`/xgh-curate` to capture what you learned

*Run `/xgh-help` anytime to see this guide.*
```

### 2.4 Init Flow Update

Add Step 6b after codebase indexing (current step 6):

**Step 6b: Initial Curation**
- Prompt: "Want to curate any initial knowledge? (architecture decisions, team conventions, known gotchas)"
- If yes, invoke `/xgh-curate` interactively
- If skip, move on

Update `commands/init.md` and `skills/init/init.md` to include this step.

## 3. Files to Change

### New files
- `commands/help.md` — the help command
- `skills/help/help.md` — (optional, if help needs a skill backing)

### Renamed files (commands/)
- `briefing.md` → `brief.md`
- `implement-design.md` → `design.md`
- `query.md` → `ask.md`
- `collaborate.md` → `collab.md`
- `team-profile.md` → `profile.md`
- `ingest-track.md` → `track.md`
- `ingest-doctor.md` → `doctor.md`
- `ingest-retrieve.md` → `retrieve.md`
- `ingest-analyze.md` → `analyze.md`
- `ingest-index-repo.md` → `index.md`
- `ingest-calibrate.md` → `calibrate.md`

### Renamed files (skills/)
- `skills/briefing/briefing.md` → `skills/brief/brief.md`
- `skills/implement-design/implement-design.md` → `skills/design/design.md`
- `skills/query-strategies/query-strategies.md` → `skills/ask/ask.md`
- `skills/agent-collaboration/instructions.md` → `skills/collab/collab.md`
- `skills/team-profile/team-profile.md` → `skills/profile/profile.md`
- `skills/curate-knowledge/curate-knowledge.md` → `skills/curate/curate.md`
- `skills/implement-ticket/implement-ticket.md` → `skills/implement/implement.md`
- `skills/ingest-track/ingest-track.md` → `skills/track/track.md`
- `skills/ingest-doctor/ingest-doctor.md` → `skills/doctor/doctor.md`
- `skills/ingest-retrieve/ingest-retrieve.md` → `skills/retrieve/retrieve.md`
- `skills/ingest-analyze/ingest-analyze.md` → `skills/analyze/analyze.md`
- `skills/ingest-index-repo/ingest-index-repo.md` → `skills/index/index.md`
- `skills/ingest-calibrate/ingest-calibrate.md` → `skills/calibrate/calibrate.md`

### Skills kept as-is (names already match convention)
- `skills/init/init.md`
- `skills/investigate/investigate.md`
- `skills/mcp-setup/mcp-setup.md`
- `skills/context-tree-maintenance/`
- `skills/continuous-learning/`
- `skills/convention-guardian/`
- `skills/cross-team-pollinator/`
- `skills/knowledge-handoff/`
- `skills/memory-verification/`
- `skills/onboarding-accelerator/`
- `skills/pr-context-bridge/`
- `skills/subagent-pair-programming/`

### Deleted files
- `commands/xgh-collaborate.md` (duplicate)

### Updated files (output style)
All remaining command .md files need their output format instructions updated to use the markdown style guide (section 2.2). This means rewriting the "display" sections of:
- `commands/status.md`
- `commands/init.md` (also add curate step)
- `commands/brief.md`
- `commands/setup.md`
- `commands/curate.md`
- `commands/investigate.md`
- `commands/implement.md`
- `commands/design.md`
- `commands/ask.md`
- `commands/collab.md`
- `commands/profile.md`
- `commands/track.md`
- `commands/doctor.md`
- `commands/retrieve.md`
- `commands/analyze.md`
- `commands/index.md`
- `commands/calibrate.md`

### Updated references
- `techpack.yaml` — update all `id`, `source`, and `description` fields for renamed components
- `AGENTS.md` — update command references and repo structure section
- `CLAUDE.md` — update command references
- `hooks/session-start.sh` — update any command references
- `hooks/prompt-submit.sh` — update any command references
- `tests/` — update test files that reference old command names (e.g., `test-collaborate-command.sh`, `test-ingest-skills.sh`, `test-briefing.sh`)
- Cross-references within skill markdown files (skills reference each other by name)

## 4. Out of Scope

- Changing the skill logic (what the commands actually do)
- Changing the hook behavior
- Changing the installer UX (already updated separately)
- Adding new functionality beyond help + curate-in-init
