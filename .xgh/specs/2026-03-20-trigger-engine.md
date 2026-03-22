# Trigger Engine — Design Spec

**Date:** 2026-03-20
**Status:** Draft
**Goal:** IFTTT-style trigger engine for developers. When events happen (provider data, local commands, schedules), evaluate rules and execute actions — notify, create, mutate, or dispatch agents. Declarative YAML by default, inline code as escape hatch.

---

## Context

xgh's pipeline is currently read-only: providers fetch → inbox collects → analyze classifies → briefing surfaces. The trigger engine adds a "THEN" side — when classified events match user-defined rules, execute actions automatically.

This turns xgh from a dashboard into an operator.

## Architecture

```
Providers ─→ Inbox ─→ Analyze ─→ Trigger Engine ─→ Actions
                         ↑
Local events ────────────┤  (fast path for critical triggers)
Schedule events ─────────┘
```

### Evaluation paths

| Path | Runs during | Latency | Matches on | Use for |
|------|------------|---------|------------|---------|
| Fast | Retrieve, after Step 4 (urgency scoring) | ~5min | `urgency_score`, `source`, raw content via `match:` keywords. `type:` is NOT available (classification hasn't run). | P0s, build breaks, error spikes |
| Standard | Analyze, after Step 3 (classification) | ~30min | All fields: `type`, `urgency_score`, `project`, `source`, `match:` | Everything else |

Fast path triggers should NOT use `when.type:` (it will never match — classification hasn't run yet). Use `when.match:` with keyword patterns and/or `when.urgency_score:` thresholds instead.

### Action levels

Safety gates that control what triggers can do:

| Level | Can do | Requires |
|-------|--------|----------|
| `notify` | DMs, channel posts, emails | Nothing (default) |
| `create` | Issues, PRs, tickets, context-tree entries, calendar events | `action_level: create` in triggers.yaml |
| `mutate` | Merge, close, reassign, pause deploys, rollback | `action_level: mutate` in triggers.yaml |
| `autonomous` | Dispatch agents (`/xgh-investigate`, `/xgh-implement`, custom prompts) | `action_level: autonomous` in triggers.yaml |

Global config in `~/.xgh/triggers.yaml`:
```yaml
enabled: true
action_level: create          # max allowed level
fast_path: true               # evaluate critical triggers during retrieve
cooldown: 5m                  # default cooldown for all triggers
```

Individual trigger steps declare their own `action_level:`. The engine refuses to execute any step whose level exceeds the global max.

## Event Sources

### 1. Provider events (standard)

Items from the inbox, classified by the analyze skill. These are the primary event source.

The `source:` field acts as the discriminator:
- `source: local` → local event (requires `command:`)
- `source: schedule` → schedule event (requires `cron:`)
- Any other value (service name or `*`) → provider event

```yaml
when:
  source: github              # provider service name, "local", "schedule", or *
  type: p0                    # content type from analyze (or * for any)
  project: mobile             # project from ingest.yaml (or * for any)
  match:                      # optional: regex/keyword filters
    title: "blocker|critical"
    author: "!bot-*"          # ! prefix = exclude
```

### 2. Local events

Commands on the user's machine that succeed. Implemented via a Claude Code `PostToolUse` hook on Bash — when a command matches a trigger's `command:` pattern, the hook writes a lightweight event file to `~/.xgh/inbox/` with `source_type: local_command`.

```yaml
when:
  source: local
  command: "npm publish"      # regex matched against Bash commands
  exit_code: 0
```

Common patterns:

| Command pattern | What it catches |
|----------------|----------------|
| `npm publish` | npm package published |
| `gem push` | Ruby gem published |
| `cargo publish` | Rust crate published |
| `pod trunk push` | CocoaPod published |
| `brew bump-formula-pr` | Homebrew formula updated |
| `gh release create` | GitHub release cut |
| `git push.*--tags` | Tags pushed |
| `docker push` | Container image published |
| `terraform apply` | Infrastructure change |
| `kubectl apply` | K8s deployment |
| `fastlane release` | iOS/Android release pipeline |
| `firebase deploy` | Firebase deployment |
| `vercel --prod` | Vercel production deploy |
| `fly deploy` | Fly.io deployment |

### 3. Schedule events

Time-based triggers. Not reactive — proactive.

```yaml
when:
  source: schedule
  cron: "0 9 * * MON"        # every Monday at 9am
```

Use case: "Every Monday morning, summarize last week's activity and post to #team-updates."

Implementation: the scheduler (CronCreate) evaluates schedule-based triggers at each run and fires those whose cron expression matches the current time.

## Trigger YAML Schema

```yaml
# ~/.xgh/triggers/<name>.yaml

schema_version: 1                 # For forward-compatible parsing
name: P0 alert                    # Human-readable name
description: Alert on critical Jira issues  # Optional
enabled: true                     # Toggle without deleting

# ── Matching ─────────────────────────────────────────────────
when:
  source: jira                    # provider service name, "local", "schedule", or *
  type: p0                        # content type from analyze, or *
  project: mobile                 # project from ingest.yaml, or *
  match:                          # optional: regex/keyword filters on item fields
    title: "blocker|critical"
    author: "!bot-*"              # ! prefix = exclude
  # For local events:
  command: "npm publish"          # regex matched against Bash commands
  exit_code: 0
  # For schedule events:
  cron: "0 9 * * MON"

# ── Evaluation path ──────────────────────────────────────────
path: standard                    # standard (analyze, 30min) or fast (retrieve, 5min)

# ── Firing policy ────────────────────────────────────────────
cooldown: 5m                      # min gap between firings
backoff: exponential              # none | fixed | exponential
max_cooldown: 6h                  # cap the backoff
reset_after: 1h                   # reset to base cooldown after silence

# ── Actions ──────────────────────────────────────────────────
# action_level here is the PER-TRIGGER cap. Steps cannot exceed this.
# This cap itself cannot exceed the GLOBAL cap in ~/.xgh/triggers.yaml.
# Enforcement chain: global cap >= trigger cap >= step level.
action_level: autonomous          # this trigger allows up to autonomous

then:
  # Declarative actions (no code) — level: notify
  - notify: slack
    channel: "#incidents"
    message: "P0: {item.title} — {item.url}"

  # Conditional steps — level: autonomous (allowed because trigger cap is autonomous)
  - if: item.urgency_score >= 90
    dispatch: /xgh-investigate
    args: "{item.url}"

  # Inline code (escape hatch) — level: notify
  # IMPORTANT: template vars in run: blocks are passed ONLY via env vars
  # ($ITEM_TITLE, $ITEM_URL, etc.) to prevent shell injection.
  # {item.*} syntax is NOT expanded inside run: blocks — use $ITEM_* instead.
  - name: Custom webhook
    run: |
      curl -X POST "$CUSTOM_WEBHOOK" -d "{\"text\":\"$ITEM_TITLE\"}"

  # Inline with specific shell
  - name: Python processing
    shell: python3
    run: |
      import os, json
      print(json.dumps({"event": os.environ["ITEM_TITLE"]}))

  # Multi-step with provider reuse
  - name: Create issue
    provider: github-cli
    run: gh issue create --repo {repo} --title "{title}"

  # Chain result of agent dispatch
  - dispatch: /xgh-implement
    args: "{item.key}"
    on_complete:
      - notify: slack
        message: "Agent drafted plan for {item.key}"
```

### Template variables

Available in all `message:`, `run:`, `args:`, `title:`, `body:` fields:

| Variable | Source | Example |
|----------|--------|---------|
| `{item.title}` | Inbox item title | "Login broken on iOS" |
| `{item.url}` | Inbox item URL | "https://jira.example.com/MOBILE-1234" |
| `{item.source}` | Provider service name | "jira" |
| `{item.source_type}` | Content classification | "jira_issue" |
| `{item.type}` | Analyze content type | "p0" |
| `{item.project}` | Project from ingest.yaml | "mobile" |
| `{item.author}` | Item author | "alice" |
| `{item.timestamp}` | ISO timestamp | "2026-03-20T14:30:00Z" |
| `{item.urgency_score}` | Urgency score (0-100) | "92" |
| `{item.repo}` | GitHub repo (if applicable) | "extreme-go-horse/xgh" |
| `{item.number}` | Issue/PR number | "42" |
| `{item.key}` | Jira key (if applicable) | "MOBILE-1234" |
| `{item.description}` | Item body/description | "Users report..." |
| `{item.summary}` | Analyze-generated summary | "Critical login..." |
| `{item.slug}` | URL-safe slug of title | "login-broken-on-ios" |
| `{item.version}` | Version (for releases) | "2.0.0" |
| `{item.severity}` | Severity (for alerts) | "critical" |
| `{item.chat_id}` | Telegram chat ID | "123456789" |
| `{item.message_id}` | Telegram message ID | "456" |
| `{item.channel_id}` | Channel ID (Slack/Discord) | "C01ABC123" |
| `{item.thread_ts}` | Thread timestamp (Slack) | "1711234567.123456" |

**`run:` blocks:** Template vars (`{item.*}`) are NOT expanded inside `run:` blocks to prevent shell injection. Use environment variables instead: `$ITEM_TITLE`, `$ITEM_URL`, `$ITEM_SOURCE`, `$ITEM_TYPE`, `$ITEM_PROJECT`, `$ITEM_AUTHOR`, `$ITEM_TIMESTAMP`, `$ITEM_URGENCY`, `$ITEM_REPO`, `$ITEM_NUMBER`, `$ITEM_KEY`, `$ITEM_VERSION`, `$ITEM_SEVERITY`, `$TOKENS_FILE`, `$PROVIDER_DIR`.

**`{result.*}` namespace** — available only in `on_complete:` steps after a `dispatch:` action:

| Variable | Source | Example |
|----------|--------|---------|
| `{result.summary}` | Agent's final output summary | "Investigated: root cause is..." |
| `{result.status}` | Agent completion status | "done", "failed", "timeout" |
| `{result.files}` | Comma-separated list of files modified | "src/auth.ts,tests/auth.test.ts" |
| `{result.commit}` | Commit SHA if agent committed | "abc123f" |
| `{result.pr_url}` | PR URL if agent created one | "https://github.com/..." |

These are populated from the agent's structured output. If a field is unavailable, it expands to empty string.

## Declarative Actions

Built-in action types that require no code. The engine resolves the right provider tool/binary automatically.

### Communication — `notify:`

```yaml
# Slack
- notify: slack
  channel: "#incidents"
  message: "P0: {item.title}"
  thread_ts: "{item.thread_ts}"

# Telegram
- notify: telegram
  chat_id: "123456789"
  message: "P0: {item.title} — {item.url}"
  reply_to: "{item.message_id}"

# Discord
- notify: discord
  channel_id: "1234567890"
  message: "P0: {item.title}"

# Email (Gmail MCP)
- notify: gmail
  to: "team@company.com"
  subject: "Deploy failed: {item.repo}"
  body: "{item.summary}"

# DM (self — uses primary chat provider)
- notify: dm
  message: "PR needs your review"
```

### Work items — `create_issue:`, `create_pr:`

```yaml
- create_issue:
    provider: github-cli
    repo: "{item.repo}"
    title: "Upgrade {item.name} to {item.version}"
    labels: [dependency, automated]
    body: "Released: {item.url}\n\nChangelog:\n{item.description}"

- create_issue:
    provider: jira-mcp
    project: MOBILE
    type: Task
    title: "Implement updated {item.title}"

- create_pr:
    provider: github-cli
    repo: "{item.repo}"
    branch: "auto/upgrade-{item.name}"
    title: "Upgrade {item.name} to {item.version}"
```

### Mutations — `close_issue:`, `merge_pr:`, `assign:`

Require `action_level: mutate` globally.

```yaml
- close_issue:
    provider: github-cli
    repo: "{item.repo}"
    number: "{item.number}"
    comment: "Closed by trigger: stale >7 days"

- merge_pr:
    provider: github-cli
    repo: "{item.repo}"
    number: "{item.number}"
    method: squash

- assign:
    provider: jira-mcp
    issue: "{item.key}"
    assignee: "{oncall.current}"
```

### Agent dispatch — `dispatch:`

Require `action_level: autonomous` globally.

```yaml
- dispatch: /xgh-investigate
  args: "{item.url}"

- dispatch: agent
  prompt: "Review the diff at {item.url} and summarize"
  model: sonnet

- dispatch: /xgh-implement
  args: "{item.key}"
  on_complete:
    - notify: slack
      channel: "#engineering"
      message: "Agent drafted plan for {item.key}"
```

### Knowledge capture — `store:` (action level: `create`)

```yaml
- store:
    path: ".xgh/context-tree/decisions/{item.slug}.md"
    content: |
      ---
      title: "{item.title}"
      date: "{item.timestamp}"
      source: "{item.url}"
      ---
      {item.summary}

- store:
    target: lcm
    tags: [decision, automated]
    content: "{item.summary}"
```

## Firing Policy

### Backoff strategies

| Strategy | Behavior | Default for |
|----------|----------|-------------|
| `none` | Fire every time | Logging, low-noise sources |
| `fixed` | Constant cooldown (e.g., every 15m) | Steady-state monitoring |
| `exponential` | base → 2x → 4x → 8x... capped at max_cooldown | Noisy/flappy sources (default) |

### State tracking

`~/.xgh/triggers/.state.json`:
```json
{
  "p0-alert": {
    "last_fired": "2026-03-20T14:30:00Z",
    "fire_count": 3,
    "current_cooldown_seconds": 1200,
    "silenced_until": null,
    "fired_items": ["2026-03-20T14-30-00Z_p0_jira_MOBILE-1234.md"]
  }
}
```

All time values in state are in **seconds**. The `fired_items` array tracks inbox item filenames this trigger already fired for — preventing duplicate firings if the same item persists across analyze cycles. The array is capped at 100 entries (oldest evicted).

### Error handling for action steps

When a `then:` step fails (non-zero exit, API error, MCP timeout):

| Policy | Behavior |
|--------|----------|
| `on_error: continue` | Log error, proceed to next step (default) |
| `on_error: abort` | Log error, skip remaining steps |
| `on_error: retry` | Retry once after 5s, then continue |

Set per-step or per-trigger (trigger-level applies to all steps without their own override).

### Manual control

- `/xgh-trigger silence <name> <duration>` — suppress a trigger temporarily
- `/xgh-trigger list` — show all triggers with status and last-fired time
- `/xgh-trigger test <name>` — dry-run a trigger against the latest matching inbox item
- `/xgh-trigger history <name>` — show firing history

## Trigger Generation

During `/xgh-track`, after generating a provider, the agent suggests triggers based on the provider type and user role:

```
GitHub provider generated. Suggested triggers:

  1. PR review reminder (>24h awaiting review) → DM you
  2. CI failure on main → alert #engineering
  3. Security alert (critical) → DM you + create issue
  4. New release on dependency repos → create upgrade issue

Enable any? [1,2,3,4 / all / none]
```

User selects, agent writes YAML to `~/.xgh/triggers/`. Users can hand-edit or add custom triggers later.

## Telegram Bot Integration

Telegram messages received by the telegram MCP plugin can fire triggers:

```yaml
- name: Telegram brief command
  when:
    source: telegram
    match:
      content: "^/brief"
  then:
    - dispatch: /xgh-brief
    - notify: telegram
      chat_id: "{item.chat_id}"
      message: "{result.summary}"
```

This makes xgh a Telegram bot that responds to commands by dispatching skills and replying with results.

## File Locations

| Path | Purpose | Owned by |
|------|---------|----------|
| `~/.xgh/triggers/` | Trigger YAML files | User (never touched by installer) |
| `~/.xgh/triggers.yaml` | Global config (enabled, action_level, cooldown) | User |
| `~/.xgh/triggers/.state.json` | Firing state (cooldowns, counts, silence) | Engine (auto-managed) |

## Integration Points

| Component | Change needed |
|-----------|--------------|
| `skills/analyze/analyze.md` | Add trigger evaluation step after classification |
| `skills/retrieve/retrieve.md` | Add fast-path trigger evaluation for critical triggers |
| `hooks/` | Add `PostToolUse` hook for local command event capture |
| `skills/track/track.md` | Add trigger suggestion step after provider generation |
| `skills/doctor/doctor.md` | Add trigger health check (enabled, firing, errors) |
| `skills/schedule/schedule.md` | Add schedule-event trigger evaluation |
| New: `skills/trigger/trigger.md` | Trigger management skill (`/xgh-trigger`) |

## Post-Publish Lifecycle Example

```yaml
- name: npm post-publish
  when:
    source: local
    command: "npm publish"
    exit_code: 0
  then:
    - name: Tag release
      provider: github-cli
      run: |
        VERSION=$(node -p "require('./package.json').version")
        gh release create "v$VERSION" --generate-notes
    - name: Update Homebrew
      run: brew bump-formula-pr --version $VERSION
    - name: Notify team
      notify: slack
      channel: "#releases"
      message: "Published {package.name}@{package.version}"
    - name: Post to Telegram
      notify: telegram
      chat_id: "123456789"
      message: "Released {package.name}@{package.version}"
```

## Scope

**In scope:**
- Trigger YAML schema and evaluation engine
- Three event sources: provider, local, schedule
- Four action levels with global gating
- Declarative actions: notify (Slack, Telegram, Discord, Gmail, DM), create_issue, create_pr, assign, close_issue, merge_pr, store
- Agent dispatch with on_complete chaining
- Inline code execution (bash, python, any shell)
- Exponential backoff and manual silence
- Trigger generation during `/xgh-track`
- `/xgh-trigger` management skill
- Trigger health checks in `/xgh-doctor`
- Telegram bot command handling

**Out of scope:**
- Visual trigger editor / UI
- Trigger marketplace / sharing
- Cross-user triggers (team triggers)
- Undo/rollback for mutation actions (rely on git/service history)

## Risk

**Medium-high.** Triggers that write to external services (create issues, merge PRs, send messages) have real-world consequences. Mitigations:

- Action levels gate dangerous operations behind explicit opt-in
- Exponential backoff prevents runaway triggers
- Manual silence provides an emergency stop
- `/xgh-trigger test` allows dry-run validation
- All trigger firings are logged for audit
- Individual steps can't exceed the global action_level cap

**Highest risk area:** `action_level: autonomous` (agent dispatch). An agent dispatched by a trigger can take further actions. The chain trigger → agent → actions multiplies risk. Mitigation: agents dispatched by triggers inherit the trigger's action_level cap — they can't escalate beyond what the trigger is allowed to do.
