# Help Command, Command Rename, and Output Refresh — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename 18 commands to a clean two-tier structure, add a contextual `/xgh-help`, enforce 🐴🤖 markdown output style across all commands, and add a curate step to init.

**Architecture:** Rename source files in `commands/` and `skills/`, update cross-references in techpack.yaml/AGENTS.md/tests/skill internals, rewrite output format instructions in every command .md to use the new markdown style guide, then add the new help command and init update.

**Tech Stack:** Markdown (Claude Code commands/skills), YAML (techpack), Bash (tests)

**Spec:** `docs/superpowers/specs/2026-03-15-help-command-and-output-refresh.md`

---

## Chunk 1: File Renames

Mechanical renames — no content changes yet. Each task is independent.

### Task 1: Rename command files

**Files:**
- Rename: `commands/briefing.md` → `commands/brief.md`
- Rename: `commands/implement-design.md` → `commands/design.md`
- Rename: `commands/query.md` → `commands/ask.md`
- Rename: `commands/collaborate.md` → `commands/collab.md`
- Rename: `commands/team-profile.md` → `commands/profile.md`
- Rename: `commands/ingest-track.md` → `commands/track.md`
- Rename: `commands/ingest-doctor.md` → `commands/doctor.md`
- Rename: `commands/ingest-retrieve.md` → `commands/retrieve.md`
- Rename: `commands/ingest-analyze.md` → `commands/analyze.md`
- Rename: `commands/ingest-index-repo.md` → `commands/index.md`
- Rename: `commands/ingest-calibrate.md` → `commands/calibrate.md`
- Delete: `commands/xgh-collaborate.md`

- [ ] **Step 1: Rename all command files**

```bash
cd /Users/pedro/Developer/tr-xgh
mv commands/briefing.md commands/brief.md
mv commands/implement-design.md commands/design.md
mv commands/query.md commands/ask.md
mv commands/collaborate.md commands/collab.md
mv commands/team-profile.md commands/profile.md
mv commands/ingest-track.md commands/track.md
mv commands/ingest-doctor.md commands/doctor.md
mv commands/ingest-retrieve.md commands/retrieve.md
mv commands/ingest-analyze.md commands/analyze.md
mv commands/ingest-index-repo.md commands/index.md
mv commands/ingest-calibrate.md commands/calibrate.md
rm commands/xgh-collaborate.md
```

- [ ] **Step 2: Verify**

```bash
ls commands/
```

Expected: `ask.md  analyze.md  brief.md  calibrate.md  collab.md  curate.md  design.md  doctor.md  implement.md  index.md  init.md  investigate.md  profile.md  retrieve.md  setup.md  status.md  track.md` (17 files)

- [ ] **Step 3: Commit**

```bash
git add -A commands/
git commit -m "rename: commands to shorter two-tier names, remove duplicate"
```

### Task 2: Rename skill directories and internal files

**Files:**
- Rename 13 skill directories + their internal .md files

- [ ] **Step 1: Rename all skill directories and internal files**

```bash
cd /Users/pedro/Developer/tr-xgh

# Everyday skills
mv skills/briefing skills/brief
mv skills/brief/briefing.md skills/brief/brief.md

mv skills/implement-design skills/design
mv skills/design/implement-design.md skills/design/design.md

mv skills/query-strategies skills/ask
mv skills/ask/query-strategies.md skills/ask/ask.md

mv skills/agent-collaboration skills/collab
mv skills/collab/instructions.md skills/collab/collab.md

mv skills/team-profile skills/profile
mv skills/profile/team-profile.md skills/profile/profile.md

mv skills/curate-knowledge skills/curate
mv skills/curate/curate-knowledge.md skills/curate/curate.md

mv skills/implement-ticket skills/implement
mv skills/implement/implement-ticket.md skills/implement/implement.md

# Admin skills
mv skills/ingest-track skills/track
mv skills/track/ingest-track.md skills/track/track.md

mv skills/ingest-doctor skills/doctor
mv skills/doctor/ingest-doctor.md skills/doctor/doctor.md

mv skills/ingest-retrieve skills/retrieve
mv skills/retrieve/ingest-retrieve.md skills/retrieve/retrieve.md

mv skills/ingest-analyze skills/analyze
mv skills/analyze/ingest-analyze.md skills/analyze/analyze.md

mv skills/ingest-index-repo skills/index
mv skills/index/ingest-index-repo.md skills/index/index.md

mv skills/ingest-calibrate skills/calibrate
mv skills/calibrate/ingest-calibrate.md skills/calibrate/calibrate.md
```

- [ ] **Step 2: Verify each directory has matching .md file**

```bash
for d in skills/*/; do
  name=$(basename "$d")
  if [ ! -f "${d}${name}.md" ] && [ "$name" != ".gitkeep" ]; then
    echo "MISMATCH: ${d} — expected ${name}.md"
  fi
done
```

Expected: No MISMATCH output (non-renamed skills like `init/init.md`, `investigate/investigate.md` already match)

- [ ] **Step 3: Commit**

```bash
git add -A skills/
git commit -m "rename: skill directories to shorter names with matching .md files"
```

### Task 3: Update techpack.yaml

**Files:**
- Modify: `techpack.yaml`

- [ ] **Step 1: Update all renamed source paths, ids, and descriptions**

Update every component that references a renamed skill or command. Change:
- `id` fields (e.g., `briefing-skill` → `brief-skill`)
- `source` fields (e.g., `skills/briefing/briefing.md` → `skills/brief/brief.md`)
- `description` fields where they reference old command names (e.g., `/xgh-briefing` → `/xgh-brief`)

Components to update:

| Old id | New id | Old source | New source |
|--------|--------|-----------|-----------|
| `briefing-skill` | `brief-skill` | `skills/briefing/briefing.md` | `skills/brief/brief.md` |
| `briefing-command` | `brief-command` | `commands/briefing.md` | `commands/brief.md` |
| `ingest-retrieve-skill` | `retrieve-skill` | `skills/ingest-retrieve/ingest-retrieve.md` | `skills/retrieve/retrieve.md` |
| `ingest-analyze-skill` | `analyze-skill` | `skills/ingest-analyze/ingest-analyze.md` | `skills/analyze/analyze.md` |
| `ingest-track-skill` | `track-skill` | `skills/ingest-track/ingest-track.md` | `skills/track/track.md` |
| `ingest-doctor-skill` | `doctor-skill` | `skills/ingest-doctor/ingest-doctor.md` | `skills/doctor/doctor.md` |
| `ingest-index-repo-skill` | `index-skill` | `skills/ingest-index-repo/ingest-index-repo.md` | `skills/index/index.md` |
| `ingest-calibrate-skill` | `calibrate-skill` | `skills/ingest-calibrate/ingest-calibrate.md` | `skills/calibrate/calibrate.md` |
| `ingest-retrieve-command` | `retrieve-command` | `commands/ingest-retrieve.md` | `commands/retrieve.md` |
| `ingest-analyze-command` | `analyze-command` | `commands/ingest-analyze.md` | `commands/analyze.md` |
| `ingest-track-command` | `track-command` | `commands/ingest-track.md` | `commands/track.md` |
| `ingest-doctor-command` | `doctor-command` | `commands/ingest-doctor.md` | `commands/doctor.md` |
| `ingest-index-repo-command` | `index-command` | `commands/ingest-index-repo.md` | `commands/index.md` |
| `ingest-calibrate-command` | `calibrate-command` | `commands/ingest-calibrate.md` | `commands/calibrate.md` |

Also add a new component for the help command:
```yaml
  - id: help-command
    type: command
    source: commands/help.md
    description: "Slash command /xgh-help — contextual guide and command reference"
```

- [ ] **Step 2: Verify no old paths remain**

```bash
grep -n "ingest-retrieve\|ingest-analyze\|ingest-track\|ingest-doctor\|ingest-index-repo\|ingest-calibrate\|briefing\|implement-design\|team-profile\|query-strategies\|agent-collaboration\|curate-knowledge\|implement-ticket" techpack.yaml
```

Expected: No matches

- [ ] **Step 3: Commit**

```bash
git add techpack.yaml
git commit -m "rename: update techpack.yaml component ids and source paths"
```

### Task 4: Update cross-references in AGENTS.md and CLAUDE.md

**Files:**
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update AGENTS.md**

Update the repository structure section and any command references. Key changes:
- `skills/` listing should show new directory names
- `commands/` listing should show new filenames
- Any `/xgh-briefing` → `/xgh-brief`, `/xgh-query` → `/xgh-ask`, etc.

- [ ] **Step 2: Update CLAUDE.md**

Update slash command references:
- `/xgh-setup` stays
- Add `/xgh-help` to the available commands list

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md CLAUDE.md
git commit -m "rename: update command references in AGENTS.md and CLAUDE.md"
```

### Task 5: Update cross-references inside skill markdown files

**Files to update (contain old command names):**
- `skills/init/init.md` (4 refs)
- `skills/collab/collab.md` (1 ref)
- `skills/profile/profile.md` (5 refs)
- `skills/brief/brief.md` (3 refs)
- `skills/continuous-learning/continuous-learning.md` (2 refs)
- `skills/curate/curate.md` (internal refs)
- `skills/pr-context-bridge/pr-context-bridge.md` (refs)
- `skills/onboarding-accelerator/onboarding-accelerator.md` (refs)
- `skills/ask/ask.md` (internal refs)
- `skills/implement/implement.md` (internal refs)
- `skills/mcp-setup/mcp-setup.md` (refs)
- `skills/subagent-pair-programming/subagent-pair-programming.md` (refs)

Also update `name:` and `description:` in frontmatter of renamed skills to match new names.

- [ ] **Step 1: Update frontmatter in all renamed skills**

For each renamed skill, update the YAML frontmatter `name:` field:
- `brief.md`: `name: xgh-brief`
- `design.md`: `name: xgh-design`
- `ask.md`: `name: xgh-ask`
- `collab.md`: `name: xgh-collab`
- `profile.md`: `name: xgh-profile`
- `curate.md`: `name: xgh-curate`
- `implement.md`: `name: xgh-implement`
- `track.md`: `name: xgh-track`
- `doctor.md`: `name: xgh-doctor`
- `retrieve.md`: `name: xgh-retrieve`
- `analyze.md`: `name: xgh-analyze`
- `index.md`: `name: xgh-index`
- `calibrate.md`: `name: xgh-calibrate`

Also update `description:` fields to use new command names where referenced.

- [ ] **Step 2: Find-and-replace old command names in all skill files**

Search and replace across all `.md` files in `skills/` and `commands/`:
- `/xgh-briefing` → `/xgh-brief`
- `/xgh-implement-design` → `/xgh-design`
- `/xgh-query` → `/xgh-ask`
- `/xgh-collaborate` → `/xgh-collab`
- `/xgh-team-profile` → `/xgh-profile`
- `/xgh-ingest-track` → `/xgh-track`
- `/xgh-ingest-doctor` → `/xgh-doctor`
- `/xgh-ingest-retrieve` → `/xgh-retrieve`
- `/xgh-ingest-analyze` → `/xgh-analyze`
- `/xgh-ingest-index-repo` → `/xgh-index`
- `/xgh-ingest-calibrate` → `/xgh-calibrate`
- `xgh:briefing` → `xgh:brief` (skill references)
- `xgh:implement-design` → `xgh:design`
- `xgh:query-strategies` → `xgh:ask`
- `xgh:agent-collaboration` → `xgh:collab`
- `xgh:team-profile` → `xgh:profile`
- `xgh:curate-knowledge` → `xgh:curate`
- `xgh:implement-ticket` → `xgh:implement`
- `xgh:ingest-track` → `xgh:track`
- `xgh:ingest-doctor` → `xgh:doctor`
- `xgh:ingest-retrieve` → `xgh:retrieve`
- `xgh:ingest-analyze` → `xgh:analyze`
- `xgh:ingest-index-repo` → `xgh:index`
- `xgh:ingest-calibrate` → `xgh:calibrate`

- [ ] **Step 3: Verify no old references remain**

```bash
grep -rn "xgh-briefing\|xgh-ingest-\|xgh-query\|xgh-team-profile\|xgh-implement-design\|xgh-collaborate\|xgh:briefing\|xgh:ingest-\|xgh:query-strategies\|xgh:team-profile\|xgh:implement-design\|xgh:agent-collaboration\|xgh:curate-knowledge\|xgh:implement-ticket" skills/ commands/
```

Expected: No matches

- [ ] **Step 4: Commit**

```bash
git add -A skills/ commands/
git commit -m "rename: update all cross-references inside skill and command files"
```

### Task 6: Update frontmatter in renamed command files

**Files:** All renamed command .md files

- [ ] **Step 1: Update `name:` field in frontmatter of each renamed command**

For each command that was renamed, update its YAML frontmatter:
- `brief.md`: `name: xgh-brief`, `description: Run a session briefing...`
- `design.md`: `name: xgh-design`, `description: Implement a UI from a Figma design...`
- `ask.md`: `name: xgh-ask`, `description: Search memory with natural language...`
- `collab.md`: `name: xgh-collab`, `description: Coordinate with other AI agents...`
- `profile.md`: `name: xgh-profile`, `description: Analyze an engineer's Jira throughput...`
- `track.md`: `name: xgh-track`, `description: Add a project to context monitoring...`
- `doctor.md`: `name: xgh-doctor`, `description: Validate pipeline health...`
- `retrieve.md`: `name: xgh-retrieve`, `description: Run retrieval loop...`
- `analyze.md`: `name: xgh-analyze`, `description: Run analysis loop...`
- `index.md`: `name: xgh-index`, `description: Index a codebase into memory...`
- `calibrate.md`: `name: xgh-calibrate`, `description: Tune dedup similarity threshold...`

- [ ] **Step 2: Commit**

```bash
git add commands/
git commit -m "rename: update command frontmatter to match new names"
```

---

## Chunk 2: Output Style Refresh

Rewrite the output format instructions in every command .md file to use the 🐴🤖 markdown style guide.

### Task 7: Define the output style guide as a reusable preamble

**Files:**
- Create: `templates/output-style.md`

- [ ] **Step 1: Write the shared style guide**

Note: `templates/` directory already exists (contains `instructions.md`).

Create `templates/output-style.md` with:

```markdown
## Output Style Guide

All `/xgh-*` command output MUST follow these formatting rules:

1. **Header:** Always start with `## 🐴🤖 xgh <command>`
2. **Subtitle:** One-line summary below the header
3. **Tables:** Use markdown tables for all structured data — never monospace alignment or indented key-value pairs
4. **Status indicators:** Use ✅ ⚠️ ❌ in table cells for pass/warn/fail
5. **Sections:** Use `###` for subsections
6. **Bold:** Bold key numbers and names in table cells
7. **Next step:** End with an italicized suggestion when relevant
8. **No dividers:** No `== xgh X ==`, `---`, or `====` text dividers
9. **Scannable:** No walls of text — tables and short sentences
```

- [ ] **Step 2: Commit**

```bash
git add templates/output-style.md
git commit -m "feat: add shared output style guide template"
```

### Task 8: Rewrite output format in `commands/status.md`

**Files:**
- Modify: `commands/status.md`

- [ ] **Step 1: Rewrite the display section**

Replace the entire "Step 4: Display Status" and "Step 5: Recommendations" sections with markdown-formatted output instructions. The command must tell Claude to output using tables with the `## 🐴🤖 xgh status` header. Include the full example output from the spec (section 2.2).

Replace the monospace `== xgh Status ==` block with the markdown table format. Replace all indented key-value displays with `| Key | Value | Status |` tables. Replace `[HEALTHY|WARNING|CRITICAL]` with ✅ ⚠️ ❌ emoji.

- [ ] **Step 2: Verify the file parses correctly (no broken markdown)**

Read the file and confirm frontmatter is valid and all tables are properly formatted.

- [ ] **Step 3: Commit**

```bash
git add commands/status.md
git commit -m "style: rewrite /xgh-status output to use markdown tables"
```

### Task 9: Rewrite output format in remaining command files

**Files:** All other command .md files (15 files)

For each command file, add an output format section at the top of the instructions (after frontmatter) that references the style guide and shows the expected output format for that specific command. At minimum, add this block after the frontmatter:

```markdown
> **Output format:** Follow the xgh output style guide. Start with `## 🐴🤖 xgh <command>`. Use markdown tables. Use ✅ ⚠️ ❌ for status. End with an italicized next step.
```

For commands that have explicit output templates (like `status.md`, `curate.md`, `doctor.md`), rewrite those templates to use the new style. For commands that don't specify output format, the one-line directive is sufficient.

- [ ] **Step 1: Add output style directive to each command file**

Files to update: `ask.md`, `analyze.md`, `brief.md`, `calibrate.md`, `collab.md`, `curate.md`, `design.md`, `doctor.md`, `implement.md`, `index.md`, `init.md`, `investigate.md`, `profile.md`, `retrieve.md`, `setup.md`, `track.md`

- [ ] **Step 2: Rewrite explicit output templates in these files**

Files with output templates that need full rewrite:
- `curate.md` — replace `== xgh Curate Complete ==` block with markdown tables
- `doctor.md` — replace monospace health check output with tables
- `init.md` — replace step-by-step plain text with tables
- `brief.md` — if it has output instructions, update to tables

- [ ] **Step 3: Verify no `== xgh` patterns remain**

```bash
grep -rn "== xgh\|== End" commands/
```

Expected: No matches

- [ ] **Step 4: Commit**

```bash
git add commands/
git commit -m "style: apply markdown output format to all command files"
```

---

## Chunk 3: New Help Command and Init Update

### Task 10: Create `/xgh-help` command

**Files:**
- Create: `commands/help.md`

- [ ] **Step 1: Write the help command**

Create `commands/help.md` with the full contextual + static guide as specified in the spec (section 2.3). The command should:

1. Start with `## 🐴🤖 xgh help`
2. **Contextual "What to do next" section** — instructions for Claude to:
   - Check `~/.xgh/ingest.yaml` exists and has non-template profile values
   - Check if projects section has entries
   - Search Cipher for repo architecture memories (indicates indexing was done)
   - Based on gaps, generate a "What to do next" table with 1-3 suggested steps
3. **Everyday Commands table** — static list of 9 commands with descriptions
4. **Setup & Admin table** — static list of 8 commands with descriptions
5. **Suggested Workflows** — 3 workflow recipes
6. End with: `*Run /xgh-help anytime to see this guide.*`

Use the exact command names and descriptions from the spec.

- [ ] **Step 2: Verify file exists and has valid frontmatter**

```bash
head -5 commands/help.md
```

Expected: Valid YAML frontmatter with `name: xgh-help`

- [ ] **Step 3: Commit**

```bash
git add commands/help.md
git commit -m "feat: add /xgh-help contextual guide and command reference"
```

### Task 11: Update init flow to include curate step

**Files:**
- Modify: `commands/init.md`
- Modify: `skills/init/init.md`

- [ ] **Step 1: Read current init files**

Read both files to understand the current step structure.

- [ ] **Step 2: Add curate step to `commands/init.md`**

After the "Index codebase" step, add:

```markdown
7. **Initial curation** (optional) — asks if you want to capture initial knowledge (architecture decisions, team conventions, known gotchas). If yes, invokes `/xgh-curate` interactively.
```

- [ ] **Step 3: Add curate step to `skills/init/init.md`**

Add the curate step to the skill's instruction flow, after codebase indexing. Include the prompt text and skip logic.

- [ ] **Step 4: Also update init output to use new style guide**

Replace any plain-text output formatting with markdown tables.

- [ ] **Step 5: Commit**

```bash
git add commands/init.md skills/init/init.md
git commit -m "feat: add curate step to /xgh-init, update output style"
```

### Task 12: Update test files

**Files:**
- Modify: tests that reference old command names

- [ ] **Step 1: Rename test files with old command names**

```bash
cd /Users/pedro/Developer/tr-xgh
mv tests/test-briefing.sh tests/test-brief.sh 2>/dev/null || true
mv tests/test-collaborate-command.sh tests/test-collab-command.sh 2>/dev/null || true
mv tests/test-ingest-skills.sh tests/test-pipeline-skills.sh 2>/dev/null || true
mv tests/test-ingest-foundation.sh tests/test-pipeline-foundation.sh 2>/dev/null || true
mv tests/test-ingest-retrieve.sh tests/test-retrieve.sh 2>/dev/null || true
mv tests/test-ingest-analyze.sh tests/test-analyze.sh 2>/dev/null || true
```

- [ ] **Step 2: Find and update references inside test files**

```bash
grep -rl "xgh-briefing\|xgh-ingest-\|xgh-query\|xgh-team-profile\|xgh-implement-design\|xgh-collaborate" tests/
```

Update any found references to use new names.

- [ ] **Step 2: Run tests to verify nothing is broken**

```bash
bash tests/test-install.sh
bash tests/test-config.sh
bash tests/test-techpack.sh
```

- [ ] **Step 3: Commit**

```bash
git add tests/
git commit -m "rename: update test files to use new command names"
```

### Task 13: Final verification and push

- [ ] **Step 1: Full grep for any remaining old references**

```bash
grep -rn "ingest-track\|ingest-doctor\|ingest-retrieve\|ingest-analyze\|ingest-index-repo\|ingest-calibrate\|xgh-briefing\|implement-design\|team-profile\|query-strategies\|agent-collaboration\|curate-knowledge\|implement-ticket\|xgh-collaborate" --include="*.md" --include="*.yaml" --include="*.json" . | grep -v ".git/" | grep -v "node_modules" | grep -v "docs/superpowers/" | grep -v ".claude/worktrees/"
```

Expected: No matches outside of docs/superpowers/ (specs/plans reference old names as history)

Note: Shell scripts (hooks) are excluded from this grep because `hooks/session-start.sh` uses `briefing` as internal variable names (`briefingTrigger`, `briefing_env`) — these are not command references and do not need renaming. The help skill (`skills/help/help.md`) is intentionally skipped — the command file alone is sufficient.

- [ ] **Step 2: Dry-run installer**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh
```

Expected: Completes without errors, lists new skill/command names

- [ ] **Step 3: Push**

```bash
git push
```
