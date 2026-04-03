# Dynamic Provider Generation — Design Spec

**Date:** 2026-03-20
**Status:** Draft
**Goal:** Replace static provider specs with a dynamic generation system where Claude reads tool documentation (CLI help, OpenAPI specs, MCP tool lists) and generates provider scripts on the fly. All providers live in `~/.xgh/user_providers/` with guaranteed persistence across updates.

---

## Context

xgh currently ships static `providers/*/spec.md` instruction documents that Claude reads during `/xgh-track` to generate `fetch.sh` scripts. This model has problems:

1. **Maintenance burden** — specs drift as CLIs and APIs evolve
2. **Incomplete coverage** — GitHub spec covers 5 of 8 desired data sources
3. **No validation** — generated scripts are never tested before use
4. **Limited extensibility** — adding a new service means writing a new spec from scratch

The dynamic model eliminates static specs entirely. Claude reads the tool's own documentation at generation time, so the generated scripts always match the current API.

## Architecture

### Provider identity

A provider is identified by `<service>-<mode>`:

| Component | Meaning | Examples |
|-----------|---------|---------|
| service | What you're talking to | github, slack, jira, linear, my-internal-tool |
| mode | How you're talking to it | cli, api, mcp |

Directory: `~/.xgh/user_providers/<service>-<mode>/`

One active provider per service. If the user tries to add `github-mcp` when `github-cli` exists, warn and offer to replace.

### Access modes

**CLI (`mode: cli`):**
Claude runs `<binary> --help` and targeted subcommand help (e.g., `gh pr list --help`, `gh run list --help`) to understand available commands, flags, and output formats. Generates a `fetch.sh` that calls the CLI binary with appropriate flags, parses output with `jq`/`grep`/`awk`, and writes inbox items.

**OpenAPI (`mode: api`):**
Claude fetches the OpenAPI/Swagger spec from a URL provided by the user. Identifies `GET` collection endpoints with date/cursor filter parameters. Generates a `fetch.sh` that calls those endpoints with `curl` + `jq`, handling pagination and authentication.

**MCP (`mode: mcp`):**
Claude reads the MCP server's available tools (via `claude mcp list` or the tool list in the current session). Identifies read/list/search tools. Generates a `provider.yaml` with MCP tool definitions — no `fetch.sh` needed. Retrieval is driven by Claude calling those tools directly during `/xgh-retrieve`.

### Auto-detection

For popular services, `/xgh-track` auto-detects available access methods before asking the user. Detection recipes are embedded in the track skill (not in separate spec files).

**Detection sequence per service:**

| Service | CLI probe | MCP probe | API probe |
|---------|-----------|-----------|-----------|
| GitHub | `command -v gh && gh auth status` | Check session tool list for `github` tools | — |
| Slack | — | Check session tool list for `slack_` tools | Check `tokens.env` for `SLACK_BOT_TOKEN` |
| Jira | — | Check session tool list for `getJiraIssue` or `atlassian` tools | — |
| Confluence | — | Check session tool list for `confluence` or `atlassian` tools | — |
| Figma | — | Check session tool list for `figma` or `get_design_context` tools | — |
| Linear | `command -v linear` | Check session tool list for `linear` tools | User provides URL |
| Generic | Ask user for binary name | Ask user for MCP server name | Ask user for OpenAPI URL |

When multiple access methods are found, recommend the best fit:
- **CLI-first services** (GitHub, Linear): CLI is richer — more endpoints, better filtering, offline-capable
- **OAuth-first services** (Slack, Jira, Confluence, Figma): MCP is richer — real-time, no token management, thread following
- Let the user confirm or override the recommendation.

When nothing is detected, fall back to asking: "How do I talk to this service? CLI binary, OpenAPI endpoint, or MCP server?"

### Generation flow

```
User: "Add GitHub"
  → Auto-detect: gh CLI found, authenticated as @tokyo-megacorp
  → Read docs: gh --help, gh pr list --help, gh issue list --help,
    gh run list --help, gh api --help (for security alerts, discussions)
  → Ask user: "Which repos?" → reads from ingest.yaml project config
  → Ask user: "Which sources?" → suggest based on my_role
    (maintainer=all, observer=releases+issues, etc.)
  → Generate: provider.yaml + fetch.sh
  → Validate: run fetch.sh with cursor=now, confirm exit 0 (0 items is valid for quiet repos)
  → Save to ~/.xgh/user_providers/github-cli/
```

### Per-repo configuration

Each repo in `provider.yaml` specifies which sources to fetch and optional filters. This is derived from the project's `github_sources`, `watch_prs`, and `watch_issues` in `ingest.yaml`.

```yaml
# ~/.xgh/user_providers/github-cli/provider.yaml
service: github
mode: cli
binary: gh
cursor_strategy: iso8601
repos:
  - owner: tokyo-megacorp
    repo: xgh
    sources: [issues, pull_requests, discussions, actions, security_alerts, releases]
    watch_prs: [19]
  - owner: mksglu
    repo: context-mode
    sources: [issues, pull_requests, releases, mentions]
    watch_prs: [136, "search:openclaw"]
    watch_issues: ["search:openclaw"]
  - owner: rtk-ai
    repo: rtk
    sources: [releases, issues]
```

When `watch_prs` or `watch_issues` contain `search:<query>` entries, the generated `fetch.sh` uses search/filter flags (e.g., `gh pr list --search openclaw`) instead of listing all items.

## provider.yaml schema

All three modes share a common header; mode-specific fields follow.

### Common fields (required)

```yaml
service: github          # Service name (used in inbox source field)
mode: cli                # cli | api | mcp
cursor_strategy: iso8601 # iso8601 | unix_ts | page_token | custom
```

### CLI mode

```yaml
service: github
mode: cli
binary: gh                # CLI binary name (must be in PATH)
cursor_strategy: iso8601
repos:                    # Per-repo config (optional — some CLIs are global)
  - owner: tokyo-megacorp
    repo: xgh
    sources: [issues, pull_requests, actions, security_alerts, discussions, releases]
    watch_prs: [19]       # Always-fetch PR numbers + search queries
    watch_issues: []      # Always-fetch issue search queries
```

### API mode

```yaml
service: linear
mode: api
base_url: https://api.linear.app
auth:
  type: bearer            # bearer | basic | header | query_param
  token_env: LINEAR_API_KEY  # Env var name in tokens.env
cursor_strategy: iso8601
endpoints:
  - name: issues
    path: /issues
    method: GET
    params:
      filter: '{"updatedAt": {"gt": "{cursor}"}}'
      first: 50
    pagination:
      type: cursor         # cursor | offset | link_header
      next_field: pageInfo.endCursor
      has_more_field: pageInfo.hasNextPage
    item_mapping:
      source_type: linear_issue
      title: "{item.title}"
      url: "{item.url}"
      author: "{item.creator.name}"
      timestamp: "{item.updatedAt}"
```

### MCP mode

```yaml
service: slack
mode: mcp
mcp_server: slack         # MCP server name (as registered)
cursor_strategy: unix_ts
tools:
  channels:
    tool: slack_read_channel
    params:
      channel: "{channel_id}"
      oldest: "{cursor}"
  threads:
    tool: slack_read_thread
    params:
      channel_id: "{channel_id}"
      ts: "{message_ts}"
```

## The fetch.sh contract

Every bash-mode provider's `fetch.sh` must follow this contract. This is what `retrieve-all.sh` depends on — it's the stable interface between generation and execution.

### Input

| Mechanism | Description |
|-----------|-------------|
| `CURSOR_FILE` env var | Path to cursor file (e.g., `~/.xgh/user_providers/github-cli/cursor`). Contains a single value (ISO timestamp, message ts, page token — depends on `cursor_strategy`). Empty or missing = first run, fetch default lookback. |
| `INBOX_DIR` env var | Path to inbox directory (`~/.xgh/inbox/`). Write items here. |
| `PROVIDER_DIR` env var | Path to provider directory. Read `provider.yaml` for configuration. |
| `TOKENS_FILE` env var | Path to `~/.xgh/tokens.env`. Source this if API tokens are needed. |

`retrieve-all.sh` sets all four env vars before invoking each `fetch.sh`:

```bash
for dir in "$PROVIDER_BASE"/*/; do
    name=$(basename "$dir")
    mode=$(grep '^mode:' "$dir/provider.yaml" 2>/dev/null | awk '{print $2}')
    # Run any provider with a fetch.sh (cli or api mode). Skip mcp (no fetch.sh).
    [ "$mode" = "cli" ] || [ "$mode" = "api" ] || continue
    script="$dir/fetch.sh"
    [ -x "$script" ] || continue

    export PROVIDER_DIR="$dir"
    export CURSOR_FILE="$dir/cursor"
    export INBOX_DIR="$HOME/.xgh/inbox"
    export TOKENS_FILE="$HOME/.xgh/tokens.env"

    rc=0
    run_with_timeout 30 bash "$script" 2>>"$HOME/.xgh/logs/provider-$name.log" || rc=$?
    # ... existing success/fail counting logic
done
```

### Output

**Inbox items:** One markdown file per item in `$INBOX_DIR/`:

Filename: `{iso_timestamp}_{source_type}_{service}_{unique_id}.md`

Format (compatible with existing inbox schema):
```markdown
---
type: github_pr
source_type: github_pr
source: github
repo: tokyo-megacorp/xgh
project: xgh
title: "feat: add dynamic provider generation"
url: https://github.com/tokyo-megacorp/xgh/pull/42
author: tokyo-megacorp
timestamp: 2026-03-20T14:30:00Z
urgency_score: 0
processed: false
tags: []
---

PR #42 opened by @tokyo-megacorp in tokyo-megacorp/xgh

feat: add dynamic provider generation

Description:
Replace static provider specs with dynamic generation...

Labels: enhancement
Reviews: 0 approved, 1 changes_requested
```

Key frontmatter fields:
- `type` / `source_type` — content classification (used by analyze)
- `source` — service name (github, slack, jira, etc.)
- `project` — which ingest.yaml project this item belongs to (used for scoping)
- `processed` — set to `false` by fetch, set to `true` by analyze after processing
- `timestamp` — ISO 8601, used for cursor advancement and sorting

**Cursor update:** Write the new cursor value (timestamp of the most recent item fetched) to `$CURSOR_FILE` on success. On partial failure (some repos succeeded, some failed), advance cursor to the oldest successful timestamp to avoid data loss.

**Exit codes:**
- `0` — success (may have fetched 0 items if nothing new)
- `1` — total failure (no items fetched, logged by retrieve-all.sh)
- `2` — partial failure (some repos succeeded, some failed — cursor partially advanced, error details in stderr)

**Stdout:** Item count for logging: `fetched=N` (e.g., `fetched=12`)

**Stderr:** Error details for provider-specific log file (auth failures, rate limits, timeouts).

### Error handling

- **Auth failure:** Log to stderr, exit 1. `/xgh-doctor` detects stale providers via error logs.
- **Rate limiting:** If `gh` returns 403/429, log the limit reset time to stderr, exit 2. Don't advance cursor for rate-limited repos.
- **Network timeout:** `retrieve-all.sh` enforces a 30-second timeout per provider. If `fetch.sh` is killed, cursor is not advanced (safe — next run retries).
- **Partial repo failure:** If 3 of 5 repos succeed, write inbox items for the 3, advance cursor for those 3 only (per-repo cursor tracking in `cursor` file as JSON: `{"tokyo-megacorp/xgh": "2026-03-20T14:30:00Z", "rtk-ai/rtk": "2026-03-20T13:00:00Z"}`), exit 2.

### Deduplication

Filename encodes the unique ID (PR number, issue number, notification ID). If a file with that name already exists in `$INBOX_DIR/`, skip it. This prevents double-stashing on overlapping fetch windows.

## MCP-mode providers

MCP providers have no `fetch.sh`. Their `provider.yaml` declares which MCP tools to use:

```yaml
service: slack
mode: mcp
mcp_server: slack
tools:
  channels:
    tool: slack_read_channel
    params:
      channel: "{channel_id}"
      oldest: "{cursor}"
  threads:
    tool: slack_read_thread
    params:
      channel_id: "{channel_id}"
      ts: "{message_ts}"
  search:
    tool: slack_search_public_and_private
    params:
      query: "{query}"
```

**MCP orchestration:** MCP providers are consumed by the `/xgh-retrieve` skill (Claude-powered, runs via CronCreate). The retrieve skill:
1. Scans `~/.xgh/user_providers/` for `mode: mcp` providers
2. Reads their `provider.yaml` to discover which MCP tools to call
3. Calls the declared tools with cursor-based parameters
4. Writes inbox items in the same frontmatter format as bash providers
5. Advances the provider's cursor file

This is a new loop in the retrieve skill — the existing Slack/Jira/Figma handling is currently hardcoded. This spec brings MCP retrieval into scope: the retrieve skill must be updated to read MCP provider configs generically rather than hardcoding service-specific tool calls. The MCP `provider.yaml` is the contract between generation and consumption.

**Note:** MCP providers require a Claude session to run (CronCreate), unlike bash providers which run headlessly. This is inherent to the MCP model — the tools are only available inside a Claude session.

### Tool role conventions

The `tools:` keys in MCP provider.yaml use **convention-based names** that the retrieve skill understands. Roles map to **data patterns**, not specific tools — the same role works across many services.

#### Communication

| Key | Role | Retrieve behavior | Example tools |
|-----|------|------------------|---------------|
| `channels` | Channel/feed scan | Fetch messages since cursor, iterate all configured channels | Slack, Discord, Teams |
| `threads` | Thread follow-up | For messages with `latest_reply > cursor`, fetch full thread replies | Slack threads, Discord threads |
| `search` | Free-text search | Query for mentions, keywords, or specific items | Any service with search API |
| `mail` | Email messages | Fetch recent emails matching filters (to:me, label, etc.) | Gmail, Outlook |

#### Work items

| Key | Role | Retrieve behavior | Example tools |
|-----|------|------------------|---------------|
| `list` | List items | Fetch items updated since cursor (issues, tickets, tasks) | Jira, Linear, Asana, GitHub Issues |
| `comments` | Comments on items | Fetch new comments on tracked items (PRs, tickets, designs, docs) | GitHub PR comments, Jira comments, Figma comments |
| `reviews` | Reviews/feedback | Fetch new reviews (code reviews, app store reviews, beta feedback) | GitHub PR reviews, App Store Connect, Google Play Console, TestFlight |

#### Documents & design

| Key | Role | Retrieve behavior | Example tools |
|-----|------|------------------|---------------|
| `files` | File/design feed | Fetch recently modified files/pages/designs since cursor | Figma, Confluence, Notion, Google Docs |
| `versions` | Version history | Detect new versions/revisions since cursor | Figma version history, Confluence page versions |

#### Operations & monitoring

| Key | Role | Retrieve behavior | Example tools |
|-----|------|------------------|---------------|
| `alerts` | Errors/incidents | Fetch new errors, incidents, or security advisories since cursor | Sentry, PagerDuty, Datadog, Dependabot |
| `deployments` | Build/deploy status | Fetch deployment or CI/CD run status since cursor | GitHub Actions, Vercel, Netlify, CircleCI |
| `releases` | Published versions | Fetch new releases, tags, or published packages | GitHub Releases, npm, PyPI, crates.io, App Store Connect |

#### Activity & analytics

| Key | Role | Retrieve behavior | Example tools |
|-----|------|------------------|---------------|
| `feeds` | Activity/notification feed | Fetch notification or activity stream since cursor | GitHub notifications, GitLab activity |
| `events` | Calendar/scheduled items | Fetch upcoming events within a time window | Google Calendar, Outlook Calendar |
| `metrics` | Analytics snapshots | Fetch key metrics periodically (download counts, error rates, revenue) | PostHog, Mixpanel, Stripe, RevenueCat |

#### AI agents

| Key | Role | Retrieve behavior | Example tools |
|-----|------|------------------|---------------|
| `sessions` | Agent session history | Fetch recent agent sessions — what was worked on, files modified, decisions made | Claude Code (`.claude/` JSONL), Codex CLI, Gemini CLI |
| `tasks` | Agent task status | Fetch dispatched task results, completion status, error reports | Codex tasks, Claude Agent SDK, Devin |
| `artifacts` | Agent-produced outputs | Fetch code, reviews, analyses, plans generated by other agents | Any agent that writes files or returns structured output |
| `decisions` | Agent reasoning | Fetch architectural choices, tradeoffs, and reasoning chains logged by agents | lossless-claude memories, agent decision logs |

This makes xgh a **meta-agent** — it tracks what other AI agents are doing across your projects. Use cases:
- **Multi-agent coordination:** Codex is refactoring module A while Gemini CLI writes tests for module B. xgh knows both are in flight, surfaces conflicts, and prevents duplicate work.
- **Agent audit trail:** What did the overnight Codex run change? What decisions did it make? xgh's briefing surfaces this alongside human Slack activity.
- **Cross-agent memory:** Agent A discovered a pattern. xgh stores it. Agent B (different tool, different session) can find it via `/xgh-ask`.

Agent providers work like any other provider:
- **CLI mode:** Parse agent session logs from disk (Claude Code's `.claude/projects/` JSONL, Codex output dirs)
- **API mode:** Query agent task APIs (Codex API, Claude Agent SDK status endpoints)
- **MCP mode:** If the agent exposes an MCP server (like lossless-claude), read its tools directly

The retrieve skill checks for these keys by name. If `threads` exists, it runs the thread-following logic (24h lookback pass in fast retrieve, 7-day scan in deep-retrieve). If not (e.g., a GitHub CLI provider has no thread concept), thread logic is skipped entirely.

Keys are additive — a provider can declare any combination. A Slack provider might have `channels` + `threads` + `search`. A Sentry provider might have just `alerts`. An App Store Connect provider might have `reviews` + `releases` + `metrics`.

This keeps orchestration logic in the skill and tool discovery in the provider config — providers declare capabilities, skills decide how to use them.

## Persistence guarantee

`~/.xgh/user_providers/` is user-owned data. The xgh plugin installer (`claude plugin install xgh@tokyo-megacorp`) and `/xgh-init` must NEVER delete, overwrite, or modify files in this directory. Only `/xgh-track` and `/xgh-track --regenerate` touch it, and only with user confirmation.

This guarantee must be documented in:
- `skills/init/init.md` — do not touch `user_providers/`
- `skills/track/track.md` — only write to `user_providers/` during explicit provider setup
- `AGENTS.md` — document the persistence contract

## Regeneration

`/xgh-track --regenerate <provider-name>` re-reads the tool's documentation and regenerates `fetch.sh` (or `provider.yaml` for MCP). This handles:

- CLI tool updates (new flags, changed output format)
- API changes (new endpoints, deprecated fields)
- MCP server updates (new tools added)

The regeneration flow:
1. Read existing `provider.yaml` for current config (repos, sources, filters)
2. Re-read tool documentation (--help, OpenAPI spec, MCP tool list)
3. Generate new `fetch.sh` (or update `provider.yaml`)
4. Validate with a test fetch
5. Replace old script only after validation passes

## retrieve-all.sh changes

The orchestrator changes from scanning `~/.xgh/providers/` to scanning `~/.xgh/user_providers/`:

```bash
PROVIDER_BASE="$HOME/.xgh/user_providers"
for dir in "$PROVIDER_BASE"/*/; do
    # ... existing discovery logic, but reading from user_providers
done
```

The `PROVIDER_DIR`, `CURSOR_FILE`, and `INBOX_DIR` env vars are set per provider before running `fetch.sh`.

## Migration from old providers

If `~/.xgh/providers/` exists with content, `/xgh-track` or `/xgh-doctor` should detect it and offer migration:

```
Found legacy providers in ~/.xgh/providers/:
  github/ slack/

Migrate to ~/.xgh/user_providers/? [Y/n]
```

Migration renames directories to `<service>-<mode>` format by reading each `provider.yaml` for the `mode` field. If `mode` is missing, infer from whether `fetch.sh` exists (cli) or only `provider.yaml` with `mcp:` section (mcp). Legacy `mode: bash` values are rewritten to `mode: cli` during migration.

## What gets retired

| Current file | Action |
|-------------|--------|
| `providers/github/spec.md` | Delete — replaced by dynamic generation |
| `providers/slack/spec.md` | Delete — replaced by dynamic generation |
| `providers/jira/spec.md` | Delete — replaced by dynamic generation |
| `providers/confluence/spec.md` | Delete — replaced by dynamic generation |
| `providers/figma/spec.md` | Delete — replaced by dynamic generation |
| `providers/_template/spec.md` | Delete — replaced by `_generator/` in track skill |

## GitHub-specific: the 8 data sources

For the GitHub CLI provider, these are the 8 source types the generated `fetch.sh` must handle:

| Source | gh command | Cursor filter | Inbox source_type |
|--------|-----------|---------------|-------------------|
| pull_requests | `gh pr list --repo R --json ... --search "updated:>CURSOR"` | ISO timestamp | `github_pr` |
| issues | `gh issue list --repo R --json ... --search "updated:>CURSOR"` | ISO timestamp | `github_issue` |
| notifications | `gh api /notifications --jq ...` (global, not per-repo) | `If-Modified-Since` header | `github_notification` |
| releases | `gh release list --repo R --json ... \| filter by date` | ISO timestamp | `github_release` |
| actions | `gh run list --repo R --json ... --created ">CURSOR"` | ISO timestamp | `github_action` |
| security_alerts | `gh api /repos/O/R/dependabot/alerts --jq '... \| select(.updated_at > "CURSOR")'` | ISO timestamp | `github_security` |
| discussions | `gh api graphql -f query='...'` with `updatedAt` filter | ISO timestamp | `github_discussion` |
| mentions | `gh search issues --mention @me --updated ">CURSOR"` or filter PR/issue results for @user | ISO timestamp | `github_mention` |

`watch_prs` items (numeric) are always fetched regardless of cursor: `gh pr view N --repo R --json ...`

`watch_prs` and `watch_issues` items with `search:QUERY` use: `gh pr list --repo R --search "QUERY updated:>CURSOR"`

`notifications` is a provider-level source (not per-repo) — fetched once globally via `/notifications` API. The response includes repo context, so items are tagged with the correct `project` in frontmatter.

## Testing strategy

1. **Contract tests:** Verify that generated `fetch.sh` scripts follow the contract (reads CURSOR_FILE, writes to INBOX_DIR, outputs `fetched=N`, exits 0/1)
2. **Integration test:** Generate a GitHub CLI provider for `tokyo-megacorp/xgh`, run one fetch, verify inbox items are created with correct frontmatter format
3. **Detection tests:** Verify auto-detection finds `gh` CLI when installed, finds MCP servers when registered
4. **Regeneration test:** Generate, modify config, regenerate, verify config is preserved but script is updated

## Scope

**In scope:**
- Dynamic generation engine (the `_generator/` logic in track skill)
- Auto-detection for GitHub, Slack, Jira, Confluence, Figma
- `fetch.sh` contract definition
- `provider.yaml` schema for all three modes
- `~/.xgh/user_providers/` persistence model
- `retrieve-all.sh` migration to new path
- GitHub CLI: all 8 data sources
- Retirement of static spec files
- Migration path from `~/.xgh/providers/`
- Validation step after generation

**Out of scope:**
- Pre-built provider scripts (fully dynamic, no static scripts shipped)
- Changes to analyze/briefing skills (they consume inbox items regardless of source)

**Note:** MCP-mode orchestration (generic provider.yaml-driven MCP tool dispatch in retrieve skill) IS in scope — the retrieve skill needs updating to read MCP provider configs instead of hardcoding Slack/Jira/Figma tool calls.

## Risk

**Medium.** The main risk is generation quality — Claude must produce correct, working `fetch.sh` scripts from documentation. Mitigations:
- Validation step catches broken scripts before they're saved
- The fetch.sh contract is simple and well-defined
- `gh` CLI is well-known to Claude from training data
- Regeneration provides a recovery path if a script breaks

**Low risk:** retrieve-all.sh path change is mechanical. Provider.yaml schema is backward-compatible.
