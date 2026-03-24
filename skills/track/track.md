---
name: xgh:track
description: "This skill should be used when the user runs /xgh-track or asks to 'add project', 'track project', 'monitor new project'. Interactive project onboarding — prompts for Slack channels, Jira, Confluence, Figma, and GitHub refs, validates connectivity, runs initial backfill of recent Slack history, and appends the project to ~/.xgh/ingest.yaml."
---

## Preamble — Execution mode

Follow the shared execution mode protocol in `skills/_shared/references/execution-mode-preamble.md`. Apply it to this skill's command name.

- `<SKILL_NAME>` = `track`
- `<SKILL_LABEL>` = `Track`

---

# xgh:track — Project Onboarding

Interactive skill to add a new project to xgh monitoring. Ask one question at a time.

## Step 1 — Collect project details

Ask each question below separately. Validate before moving to the next.

1. **Project name** — free text. Derive config key: lowercase, spaces → hyphens, no special chars.
   Example: "Passcode Feature" → `passcode-feature`

2. **Your role in this project** (`my_role`) — suggest common values: `ios-lead`, `mobile-lead`, `engineer`, `reviewer`, `observer`. Let the user type any value. Default to `engineer` if they skip.

3. **What you own / coordinate** (`my_intent`) — free text describing what the user owns, delegates, or coordinates in this project. Example: "I own the iOS implementation, delegate QA to the platform team, and coordinate with backend on API changes." Let the user skip with empty.

4. **Slack channels** — comma-separated channel names (with or without `#`).
   For each, verify accessibility via `slack_search_channels`. If not found, show error and re-ask.

5. **Jira project key** (optional) — e.g. `PTECH-31204`. If provided, call `getJiraIssue` with a search to verify. Show count of open issues if found.

6. **Confluence links** (optional) — paste RFC/spec/wiki URLs one per line. For each, call `getConfluencePage` to verify access, then extract key learnings as a concise summary (3-7 bullets), call lcm_store with the summary text and context-appropriate tags. Do not pass raw conversation content to lcm_store. Use tags: ["session"].

7. **Figma links** (optional) — store as plain refs (no indexing in v1).

8. **GitHub repos** (optional) — `org/repo` format. Store as refs. If provided, ask:
   `Index codebase now? [y/n]` — if yes, invoke the xgh:index skill in quick mode.

9. **Default access level** — ask: "Default access level for all providers? (`read` / `ask` / `auto`)" Default to `read` if the user skips.
   - `read` — observe only; can fetch data, never writes back to the provider.
   - `ask` — can propose write actions, but must confirm with the user first.
   - `auto` — fully autonomous writes (e.g., auto-post digests, transition tickets).
   Set all five providers (slack, jira, confluence, github, figma) to the chosen level. Note that the user can customize per-provider later in `~/.xgh/ingest.yaml`.

10. **Project dependencies** (optional) — other tracked projects this project depends on.
    Show a list of existing project names from `ingest.yaml` and let the user pick.
    Example: "xgh depends on: lossless-claude, context-mode"
    Store as `dependencies: [lossless-claude, context-mode]`.
    Default: empty list. These are used by retrieval and briefing to scope data gathering
    — when working in this project, data from its dependencies is also included.

## Step 2 — Initial backfill

Read the last 200 messages from each Slack channel using `slack_read_channel`. For each message containing a Jira/Confluence/GitHub link, stash it to `~/.xgh/inbox/` and add the ref to the enrichment list.

Show progress:
```
Scanning #ptech-31204-engineering... found 12 Jira links, 3 Confluence pages, 2 PRs
Auto-enriching project config with discovered references.
```

## Step 3 — Write to ingest.yaml

Use python3 to safely read, update, and write `~/.xgh/ingest.yaml` (read → modify dict → yaml.dump):

```yaml
projects:
  passcode-feature:
    status: active
    my_role: ios-lead
    my_intent: "Own iOS implementation, delegate QA to platform team, coordinate backend API changes"
    dependencies:            # from Q10 — other tracked projects
      - lossless-claude
      - context-mode
    providers:
      slack:      { access: read }
      jira:       { access: read }
      confluence: { access: read }
      github:     { access: read }
      figma:      { access: read }
    slack:
      - "#ptech-31204-general"
      - "#ptech-31204-engineering"
    jira: PTECH-31204
    confluence:
      - /spaces/PTECH/pages/rfc-passcode-v2
    github:
      - acme-corp/acme-ios
    figma:
      - https://figma.com/design/abc123/passcode-screens
    rfcs: []
    index:
      last_full: null
      schedule: weekly
      watch_paths: []
    last_scan: null
```

---

## Reference

### Step 3b: Generate provider scripts (dynamic)

> **Persistence guarantee:** Provider scripts are saved to `~/.xgh/user_providers/` which is NEVER
> touched by plugin installs or `/xgh-init`. Only `/xgh-track` creates or modifies provider files,
> and only with user confirmation.

For each service the user wants to track, dynamically generate a provider:

#### Auto-detection

Probe the system for available access methods:

| Service | CLI probe | MCP probe | API probe |
|---------|-----------|-----------|-----------|
| GitHub | `command -v gh && gh auth status` | Check session tool list for `github` tools | — |
| Slack | — | Check session tool list for `slack_` tools | Check `tokens.env` for `SLACK_BOT_TOKEN` |
| Jira | — | Check session tool list for `atlassian` tools | — |
| Confluence | — | Check session tool list for `atlassian` tools | — |
| Figma | — | Check session tool list for `figma` tools | — |
| Generic | Ask for binary name | Ask for MCP server name | Ask for OpenAPI URL |

Recommend the best fit:
- CLI-first services (GitHub, Linear): CLI is richer
- OAuth-first services (Slack, Jira, Confluence, Figma): MCP is richer

Report findings and let user confirm.

#### Doc reading

Based on detected mode:
- **CLI:** Run `<binary> --help` and targeted subcommand help. Parse available commands, flags, output formats.
- **API:** Fetch the OpenAPI spec URL. Identify GET collection endpoints with date filters.
- **MCP:** List available tools from the MCP server. Identify read/list/search/channels/threads tools.

#### Generation

Generate `provider.yaml` + `fetch.sh` (for cli/api) or `provider.yaml` only (for mcp):
- Directory: `~/.xgh/user_providers/<service>-<mode>/`
- `provider.yaml` schema: `service`, `mode` (cli|api|mcp), `cursor_strategy`, plus mode-specific fields
- For cli/api: `fetch.sh` follows the contract — reads `CURSOR_FILE`, `INBOX_DIR`, `PROVIDER_DIR`, `TOKENS_FILE` env vars
- Populate repos/endpoints from the project's `ingest.yaml` config

#### Validation

Run the generated fetch.sh with cursor set to now:
```bash
CURSOR_FILE="<dir>/cursor" INBOX_DIR="$HOME/.xgh/inbox" PROVIDER_DIR="<dir>" TOKENS_FILE="$HOME/.xgh/tokens.env" bash "<dir>/fetch.sh"
```
Confirm exit 0. Report results. If validation fails, show error and offer to retry or skip.

#### Conflict handling

If a provider for this service already exists:
```
You already have a GitHub provider (github-cli).
Replace it? Or rename the existing one to keep both? [Replace/Rename/Skip]
```

## Step 4 — Suggest triggers

After generating the provider(s), suggest relevant triggers based on provider type and roles.

1. Determine provider type from the generated `provider.yaml` (roles: list, alerts, prs, etc.)
2. Present 3-5 relevant trigger suggestions. Examples by role:

   **GitHub (PRs, issues, actions):**
   1. PR awaiting review >24h → DM you
   2. CI failure on main branch → notify #engineering
   3. Security alert (critical) → DM you + create GitHub issue
   4. New release on watched repo → create upgrade issue

   **Jira (list, comments):**
   1. P0/blocker issue created → notify #incidents
   2. Ticket assigned to you → DM you
   3. Sprint blocked → alert channel

   **Slack (channels, threads):**
   1. Direct mention in monitored channel → DM you with context
   2. Message matches crisis keywords → notify #incidents

   **Sentry (alerts):**
   1. Error spike (>100 in 5min) → notify #engineering
   2. New issue (critical) → create Jira ticket

   **Local (npm, cargo, gh release):**
   1. `npm publish` success → tag GitHub release + notify Slack

   **Schedule:**
   1. Monday 9am → run /xgh-brief and post summary

3. Ask: "Enable any? [1,2,3 / all / none]"
4. For each selected trigger:
   - Generate a YAML file in `~/.xgh/triggers/<provider>-<trigger-slug>.yaml`
   - Use `schema_version: 1`, `enabled: true`, appropriate `backoff: exponential`
   - Set `path: fast` only for critical/P0 triggers; `path: standard` for everything else
   - Use conservative `action_level: notify` by default; prompt to elevate if user wants create/autonomous
   - Write the file using `Write` tool
5. Confirm: "✅ Created N triggers in ~/.xgh/triggers/"
   Show the paths of created files.

## Step 5 — Confirm

Display a final summary of the completed track onboarding:

```
✅ Project tracked successfully!

Provider: <service>-<mode>  (~/.xgh/user_providers/<name>/)
Triggers: N created  (~/.xgh/triggers/)

Next steps:
  • Run /xgh-retrieve to do an initial backfill
  • Run /xgh-doctor to verify the full pipeline is healthy
  • Edit ~/.xgh/triggers/*.yaml to customize your triggers
```

If no triggers were enabled, omit the triggers line.

## Step 6 — Scheduler Setup

Check if background scheduling is active:

1. Call CronList — check for jobs where prompt is `/xgh-retrieve` or `/xgh-analyze`.
2. Check if `~/.xgh/scheduler-paused` exists (pauses the scheduler).

**If both cron jobs exist**: show `✅ Scheduler active` and stop here.

**If jobs missing**: Ask:

```
Enable background scheduling?
  retrieve: every 5 min  (scans Slack, GitHub for new items)
  analyze:  every 30 min (classifies and stores to memory)

Jobs auto-expire after 3 days and are re-created each session automatically.

Enable? [Y/n]
```

**Dependency guard:** If `~/.xgh/scripts/retrieve-all.sh` doesn't exist yet:
1. Find it in the plugin cache: `find ~/.claude/plugins/cache -path "*/xgh/*/scripts/retrieve-all.sh" -print -quit`
2. Copy to `~/.xgh/scripts/retrieve-all.sh` and `chmod +x`

If **yes**:
1. Register CronCreate jobs immediately:
   - retrieve: `cron: "*/5 * * * *"`, `prompt: "bash ~/.xgh/scripts/retrieve-all.sh || true"`, `recurring: true`
   - analyze: `cron: "*/30 * * * *"`, `prompt: "/xgh-analyze"`, `recurring: true`
2. Remove pause file if present: `rm -f ~/.xgh/scheduler-paused`
3. Report: `✅ Scheduler enabled — retrieve (*/5) and analyze (*/30) registered.`

If **no**: `⚠️ Scheduler not enabled. Run /xgh-schedule resume anytime.`

## Regeneration

When invoked as `/xgh-track --regenerate <provider-name>`:

1. Read existing `~/.xgh/user_providers/<provider-name>/provider.yaml` for current config
2. Re-read tool documentation (--help, OpenAPI spec, MCP tool list)
3. Generate new `fetch.sh` (or update `provider.yaml`)
4. Validate with a test fetch
5. Replace old script only after validation passes
6. Report: "Regenerated <provider-name>. Config preserved, script updated."
