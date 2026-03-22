---
name: xgh:init
description: >
  First-run onboarding after install. Verifies MCP connections, sets up profile,
  adds first project, runs initial retrieval, and optionally profiles the team
  and indexes the codebase. Run once per project setup.
type: flexible
triggers:
  - when invoked via /xgh-init command
  - when the user says "set up xgh" or "initialize xgh" or "get started"
mcp_dependencies:
  required:
    - lossless-claude: "lossless-claude MCP — core memory (lcm_search)"
  optional:
    - slack: "Slack MCP — channel access (slack_read_channel)"
    - atlassian: "Atlassian MCP — Jira/Confluence (getJiraIssue)"
    - figma: "Figma MCP — design files (get_design_context)"
    - github: "GitHub CLI — gh command available"
---

# xgh:init — First-Run Onboarding

Welcome the user to xgh and walk them through the full first-run setup. This is their first experience with the system, so keep it conversational and clear. Ask one thing at a time, confirm each step before moving on.

Start with:

```
Welcome to xgh — the developer's cockpit.

I'll walk you through first-time setup. This takes about 5 minutes:
  0. Bootstrap (data dirs, dependencies)
  1. Verify MCP connections
  2. Set up your profile
  3. Add your first project
  4. Run initial retrieval
  5. (Optional) Profile your team
  6. (Optional) Index your codebase
  7. (Optional) Curate initial knowledge

Scheduler activates automatically after setup. Let's go.
```

---

## Step 0: Bootstrap (create data dirs + check dependencies)

### 0a. Create data directory structure

```bash
mkdir -p ~/.xgh/inbox/processed ~/.xgh/logs ~/.xgh/digests ~/.xgh/calibration ~/.xgh/user_providers ~/.xgh/triggers
```

> **Persistence guarantee:** `~/.xgh/user_providers/` is user-owned. `/xgh-init` creates
> the directory but NEVER deletes, overwrites, or modifies its contents. Only `/xgh-track`
> touches provider files, and only with user confirmation.

### 0b. Create ingest.yaml from template (if missing)

```bash
if [ ! -f ~/.xgh/ingest.yaml ]; then
  # Find the plugin cache directory
  PLUGIN_DIR=$(find ~/.claude/plugins/cache -path "*/xgh/*/config/ingest-template.yaml" -print -quit 2>/dev/null | xargs dirname 2>/dev/null)
  if [ -n "$PLUGIN_DIR" ]; then
    cp "$PLUGIN_DIR/ingest-template.yaml" ~/.xgh/ingest.yaml
    echo "Created ~/.xgh/ingest.yaml from template"
  else
    echo "Warning: ingest template not found — create ~/.xgh/ingest.yaml manually"
  fi
fi
```

### 0c. Initialize trigger global config

If `~/.xgh/triggers.yaml` does not exist, create it with defaults:

```bash
if [ ! -f ~/.xgh/triggers.yaml ]; then
  cat > ~/.xgh/triggers.yaml << 'EOF'
# ~/.xgh/triggers.yaml — Global trigger engine config
# Edit this to change what the trigger engine is allowed to do.

enabled: true
action_level: notify       # max allowed: notify | create | mutate | autonomous
fast_path: true            # evaluate critical triggers during retrieve (5min path)
cooldown: 5m               # default cooldown for all triggers
EOF
  echo "Created ~/.xgh/triggers.yaml from defaults"
fi
```

> This file is NEVER touched by plugin updates. It is yours.
> To disable all triggers: set `enabled: false`.
> To allow issue/PR creation: set `action_level: create`.
> To allow agent dispatch: set `action_level: autonomous`.

Also note: To capture local bash command events (for `source: local` triggers),
the PostToolUse hook in `hooks/post-tool-use.sh` must be registered. Run `/xgh-setup`
or add it to your Claude Code settings manually.

### 0c2. Install default trigger catalog

Copy the default triggers from `config/triggers.yaml` into `~/.xgh/triggers/` as individual runtime files. Skip files that already exist (never overwrite user edits).

```bash
TRIGGERS_CATALOG=$(find ~/.claude/plugins/cache -path "*/xgh/*/config/triggers.yaml" -print -quit 2>/dev/null)
if [ -n "$TRIGGERS_CATALOG" ]; then
  python3 - "$TRIGGERS_CATALOG" ~/.xgh/triggers << 'PY'
import sys, os, re
try:
    import yaml
except ImportError:
    print("SKIP: pyyaml not installed — run: pip3 install pyyaml", file=sys.stderr)
    sys.exit(0)
catalog_path, triggers_dir = sys.argv[1], sys.argv[2]
os.makedirs(triggers_dir, exist_ok=True)
catalog = yaml.safe_load(open(catalog_path))
for entry in catalog.get('triggers', []):
    slug = re.sub(r'[^a-z0-9]+', '-', entry['name'].lower()).strip('-')
    dest = os.path.join(triggers_dir, f"{slug}.yaml")
    if not os.path.exists(dest):
        yaml.dump(entry, open(dest, 'w'), default_flow_style=False, sort_keys=False)
        print(f"  Installed: ~/.xgh/triggers/{slug}.yaml")
    else:
        print(f"  Skipped (exists): ~/.xgh/triggers/{slug}.yaml")
PY
fi
```

> These are starter triggers only — safe to edit or delete. `/xgh-init` will never overwrite existing trigger files.

### 0d. Install static instructions (@reference)

```bash
# Find xgh-instructions.md in plugin cache
XGH_TMPL=$(find ~/.claude/plugins/cache -path "*/xgh/*/templates/xgh-instructions.md" -print -quit 2>/dev/null)
if [ -n "$XGH_TMPL" ]; then
  mkdir -p .xgh
  cp "$XGH_TMPL" .xgh/xgh.md
  # Add @reference to CLAUDE.local.md if not present
  grep -q '@.xgh/xgh.md' CLAUDE.local.md 2>/dev/null || echo -e "\n@.xgh/xgh.md" >> CLAUDE.local.md
fi
```

### 0e. Check dependencies

**lossless-claude:**

```bash
command -v lossless-claude
```

- **Found** → continue
- **Not found** → offer to install:
  ```
  lossless-claude not found. Install it?

  curl -fsSL https://raw.githubusercontent.com/extreme-go-horse/lossless-claude/main/install.sh | bash
  ```
  If user says yes, run the installer. If no, continue — memory features will be unavailable.

**RTK (optional):**

```bash
command -v rtk
```

- **Found** → continue
- **Not found** → offer to install:
  ```
  RTK not found. It saves 60-90% on token usage. Install it?

  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | bash
  rtk init -g --auto-patch
  ```
  If user says yes, run both commands. If no, skip — everything works without RTK.

### 0g. Install retrieve orchestrator

```bash
RETRIEVE_SCRIPT=$(find ~/.claude/plugins/cache -path "*/xgh/*/scripts/retrieve-all.sh" -print -quit 2>/dev/null)
if [ -n "$RETRIEVE_SCRIPT" ]; then
    mkdir -p ~/.xgh/scripts
    cp "$RETRIEVE_SCRIPT" ~/.xgh/scripts/retrieve-all.sh
    chmod +x ~/.xgh/scripts/retrieve-all.sh
    echo "Installed retrieve-all.sh"
fi
```

### 0h. Install project detector

```bash
DETECT_SCRIPT=$(find ~/.claude/plugins/cache -path "*/xgh/*/scripts/detect-project.sh" -print -quit 2>/dev/null)
if [ -n "$DETECT_SCRIPT" ]; then
    mkdir -p ~/.xgh/scripts
    cp "$DETECT_SCRIPT" ~/.xgh/scripts/detect-project.sh
    chmod +x ~/.xgh/scripts/detect-project.sh
    echo "Installed detect-project.sh"
fi
```

### 0i. Verify lossless-claude MCP registration

```bash
claude mcp list 2>/dev/null | grep -i lossless-claude
```

- **Found** → continue
- **Not found** → register it:
  ```bash
  claude mcp add lossless-claude -- lossless-claude mcp
  ```
  Report: "Registered lossless-claude MCP server."

---

## Step 0b: Stale Install Cleanup

Check for old-style per-project skill copies from pre-plugin installs:

Run in Bash:

```bash
ls .claude/skills/ 2>/dev/null | grep "^xgh-"
ls .claude/commands/ 2>/dev/null | grep "^xgh-"
```

If any `xgh-*` entries are found:

1. Remove them:
   ```bash
   rm -rf .claude/skills/xgh-* .claude/commands/xgh-* 2>/dev/null || true
   rm -f .claude/hooks/continuous-learning-activator.sh 2>/dev/null || true
   ```

2. Report: "Removed legacy per-project skill copies. Skills now load from the user-level plugin at `~/.claude/plugins/cache/extreme-go-horse/xgh/`."

If none found → continue silently.

---

## Step 0c: Legacy Provider Migration

Check for old-style provider directories:

```bash
if [ -d ~/.xgh/providers ] && [ "$(ls -A ~/.xgh/providers 2>/dev/null)" ]; then
    echo "Found legacy providers in ~/.xgh/providers/"
    ls ~/.xgh/providers/
fi
```

If legacy providers found, offer migration:
```
Legacy providers detected. Migrate to ~/.xgh/user_providers/?
This renames directories to <service>-<mode> format. [Y/n]
```

If yes: for each provider dir, read mode from provider.yaml, rename to `<service>-<mode>`, move to `~/.xgh/user_providers/`. Rewrite `mode: bash` to `mode: cli`.

If no: continue. Doctor will remind them later.

---

## Step 1 — Verify MCP Connections

Run the MCP detection protocol from the `xgh:mcp-setup` skill before proceeding.

---

## Step 2 — Profile Setup

### Check if profile is already configured

Read `~/.xgh/ingest.yaml` and check if `profile.name` exists and is not the template default (`"Your Name"`). If the profile is already filled in, show what's there and ask:

```
Profile already configured:
  Name: Pedro
  Role: engineer
  Squad: mobile

Keep this? [Y/n]
```

If they say yes, skip to Step 3. If no, re-ask the questions below.

### Collect profile info

Ask each question one at a time:

1. **Name** — "What's your name?" (free text)

2. **Slack user ID** — "What's your Slack user ID? (e.g., U01ABCDEF)"
   - If Slack MCP is available, offer: "I can try to look it up — what's your Slack display name?"
   - Use `slack_search_users` with their display name to find the user ID
   - Let them confirm or type it manually

3. **Role** — "What's your role? (engineer / lead / manager)"
   - Default to `engineer` if they skip

4. **Squad/team** — "What squad or team are you on?" (free text)

5. **Platforms** — "What platforms do you work on? (comma-separated: ios, android, web, backend)"

### Write profile

Use python3 to safely read, modify, and write `~/.xgh/ingest.yaml`:

```python
import yaml
with open(os.path.expanduser('~/.xgh/ingest.yaml'), 'r') as f:
    config = yaml.safe_load(f)
config['profile'] = {
    'name': '<name>',
    'slack_user_id': '<slack_id>',
    'role': '<role>',
    'squad': '<squad>',
    'platforms': ['ios', 'android']
}
with open(os.path.expanduser('~/.xgh/ingest.yaml'), 'w') as f:
    yaml.dump(config, f, default_flow_style=False)
```

Confirm:

```
Profile saved:
  Name: Pedro
  Slack: U01ABCDEF
  Role: engineer
  Squad: mobile
  Platforms: ios, android
```

---

## Step 3 — Add First Project

**Auto-detect current repo:** Run `git remote get-url origin 2>/dev/null` and parse `org/repo` from the URL. If found and not already in `~/.xgh/ingest.yaml`, pre-populate it as the first project to track — no need to ask.

Check if `projects:` in `~/.xgh/ingest.yaml` already has entries. If so:

```
You already have projects configured:
  - passcode-feature (active)

Add another project? [y/N]
```

If no existing projects, or auto-detected repo is not yet tracked, invoke the `/xgh-track` workflow. Follow that skill's full interactive flow:
- Pre-fill GitHub repo from auto-detected remote if available
- Collect project name, Slack channels, Jira, Confluence, GitHub, Figma sources
- Ask for `my_role` and `my_intent`
- Ask for default provider access level
- Ask for dependencies (other tracked projects)
- Run initial backfill

Wait for the `/xgh-track` flow to complete before proceeding.

### Configure dependencies for existing projects

If projects already exist and the user kept them, check if any are missing `dependencies:`. For each project without dependencies, ask:

```
Project "xgh" has no dependencies set.
Other tracked projects: lossless-claude, context-mode, rtk, inspector

Does "xgh" depend on any of these? (comma-separated, or skip)
```

This scopes retrieval and briefing — when working in a project's repo, only that project and its dependencies are fetched. Write dependencies to `ingest.yaml` using python3 (same pattern as profile write).

---

## Step 4 — Initial Retrieval

Run a single retrieval cycle to backfill recent messages from the configured channels.

```
Running initial retrieval to catch up on recent activity...
```

Follow the `xgh:retrieve` skill logic:
- Scan each configured Slack channel for recent messages
- Follow links 1-hop to Jira/Confluence/GitHub/Figma
- Stash raw content to `~/.xgh/inbox/`

Show progress:

```
Scanning #ptech-31204-general... 45 messages, 8 links found
Scanning #ptech-31204-engineering... 62 messages, 14 links found
Stashed 22 items to ~/.xgh/inbox/

Initial retrieval complete.
```

---

## Step 5 — Team Profiling (Optional)

Ask:

```
Want to profile your team members for smart task assignment?
This analyzes their Jira history to build throughput and affinity profiles.
You can skip this and do it later with /xgh-profile.

Profile team now? [y/N]
```

If **yes**:

1. Ask: "Enter engineer names (comma-separated):"
2. Verify Atlassian MCP is available. If not:
   ```
   Atlassian MCP is required for team profiling. Skipping for now.
   Run /xgh-setup to add Atlassian, then /xgh-profile to profile your team.
   ```
3. For each name provided, invoke the `xgh:profile` skill workflow.
4. Show a summary of profiles generated.

If **no** (or user skips): Continue to Step 6.

---

## Step 6 — Index Codebase (Optional)

Ask:

```
Want to index your codebase into lossless-claude memory?
This makes your code searchable for future tasks and investigations.
You can skip this and do it later with /xgh-index.

Index codebase now? [y/N]
```

If **yes**:

1. Invoke the `xgh:index` skill in **quick mode**.
2. Show indexing progress and summary.

If **no** (or user skips): Continue to Step 7.

---

## Step 7 — Initial Curation (Optional)

Ask:

```
Want to curate any initial knowledge? (architecture decisions, team conventions, known gotchas)
This captures important context that helps future sessions work better.
You can skip this and do it later with /xgh-curate.

Curate initial knowledge now? [y/N]
```

If **yes**:

1. Invoke the `xgh:curate` skill interactively.
2. Let the user capture as many items as they want.
3. When done, show a summary of what was stored.

If **no** (or user skips): Continue to Step 7a.

---

## Step 7a — Generate AGENTS.md

Always runs (not optional). Regenerates `AGENTS.md` from config files and writes platform wrapper files.

### 1. Check for the generator script

```
if scripts/gen-agents-md.sh does not exist:
    warn: "scripts/gen-agents-md.sh not found — skipping AGENTS.md generation"
    skip to Step 7b
```

### 2. Handle existing AGENTS.md

```
if AGENTS.md exists:
    if AGENTS.md starts with "<!-- AUTO-GENERATED":
        # safe to overwrite — run script normally
    else:
        prompt: "AGENTS.md exists and wasn't generated by xgh. Overwrite? [y/N]"
        if user says yes: run script
        else: skip to Step 7b
else:
    # file doesn't exist — run script normally
```

### 3. Run the generator

```bash
bash scripts/gen-agents-md.sh
```

### 4. Write platform wrapper files

After `AGENTS.md` is generated, write the following files:

**`CLAUDE.md`** — thin wrapper (only if it doesn't exist or already only contains `@AGENTS.md`):
```
@AGENTS.md
```

**`GEMINI.md`** — same content as AGENTS.md (Gemini doesn't support `@` references):
```
<copy full contents of AGENTS.md>
```

**`.github/copilot-instructions.md`** — copy of AGENTS.md content (GitHub Copilot reads this path):
```
<copy full contents of AGENTS.md>
```
Create `.github/` directory if it doesn't exist.

**`.gitignore`** — append these lines if not already present:
```
CLAUDE.md
GEMINI.md
```
(These are generated files and shouldn't be committed.)

### 5. Confirm

Show a brief summary of what was written:
```
AGENTS.md generated ✅
  CLAUDE.md       → @AGENTS.md wrapper
  GEMINI.md       → full copy
  .github/copilot-instructions.md → full copy
  .gitignore      → CLAUDE.md, GEMINI.md added
```

---

## Step 7b — Scheduler

The SessionStart hook (`hooks/session-start.sh`) automatically registers CronCreate jobs when
providers are configured. No manual setup needed.

Use `/xgh-schedule pause` to disable, `/xgh-schedule resume` to re-enable.

Verify by checking CronList after the first prompt of any new session.

If no jobs appear, check:
1. `~/.xgh/scripts/retrieve-all.sh` exists and is executable
2. At least one provider exists in `~/.xgh/user_providers/`
3. `~/.xgh/scheduler-paused` does not exist

---

## Step 8 — Summary

Print a final recap of everything that was configured:

```
xgh setup complete!

  Profile
    Name: Pedro
    Role: engineer
    Squad: mobile
    Platforms: ios, android

  Project: passcode-feature
    Channels: #ptech-31204-general, #ptech-31204-engineering
    Jira: PTECH-31204
    Confluence: 1 page linked
    GitHub: acme-corp/acme-ios

  Team Profiles: [generated for Alice, Bob / skipped]
  Codebase Index: [indexed / skipped]
  AGENTS.md:      ✅ generated (CLAUDE.md, GEMINI.md, .github/copilot-instructions.md)
  Scheduler:     ✅ active by default

  Next steps:
    - Run /xgh-brief to get your first daily briefing
    - Run /xgh-setup to add any missing MCP integrations
```

### Store in lossless-claude

If lossless-claude is available, store the onboarding completion:

```
Extract key learnings as a concise summary (3-7 bullets), then call lcm_store with the
summary text and context-appropriate tags. Do not pass raw conversation content to lcm_store.
Use tags: ["session"]
Content: "xgh init completed for <name> (<role>, <squad>). Project: <project>. Team profiles: <yes/no>. Codebase indexed: <yes/no>."
```

---

## Error Handling

- **Missing ingest.yaml:** Step 0b creates it from template. If template not found, warn the user.
- **MCP not responding:** If a tool call times out or errors, retry once. If it fails again, mark that integration as unavailable and continue.
- **User wants to stop mid-flow:** At any point, if the user says "stop" or "skip the rest", jump to Step 8 (Summary) with whatever was completed so far.
- **Partial completion:** If the user has already done some steps (profile filled, project exists), detect that and skip with a note. Never re-do work that's already been done unless the user asks.

---

## Composability

This skill chains together existing skills rather than duplicating their logic:

| Step | Delegates to |
|------|-------------|
| Step 1 — MCP checks | `xgh:mcp-setup` detection protocol |
| Step 3 — Add project | `xgh:track` full flow |
| Step 4 — Retrieval | `xgh:retrieve` single cycle |
| Step 5 — Team profiles | `xgh:profile` per engineer |
| Step 6 — Index codebase | `xgh:index` quick mode |
| Step 7 — Initial curation | `xgh:curate` interactive |
| Step 7a — Generate AGENTS.md | `bash scripts/gen-agents-md.sh` + platform wrappers |
| Step 7b — Scheduler | Auto-registered via `hooks/session-start.sh` |
