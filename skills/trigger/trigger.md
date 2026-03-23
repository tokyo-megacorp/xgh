---
name: xgh:trigger
description: "This skill should be used when the user runs /xgh-trigger or asks to list triggers, test triggers, silence noisy triggers, or view trigger firing history. Manages the xgh trigger engine — list, test, silence, and inspect trigger rules and their firing history."
---

---

# /xgh-trigger — Trigger Engine Management

Manage xgh triggers. Reads `~/.xgh/triggers/*.yaml` (user-defined rules) and
`~/.xgh/triggers/.state.json` (firing state: cooldowns, counts, silence).

## Sub-commands

### list

Show all triggers with status at a glance.

1. Read `~/.xgh/triggers.yaml` (global config: enabled, action_level, cooldown).
   If missing: warn "⚠ No global config — run /xgh-init to create ~/.xgh/triggers.yaml"
2. Read all `~/.xgh/triggers/*.yaml` files (skip `.state.json`).
3. Read `~/.xgh/triggers/.state.json` (if exists) for last_fired and silenced_until.
4. Output as a markdown table:

| Name | Source | Path | Level | Enabled | Last Fired | Status |
|------|--------|------|-------|---------|-----------|--------|
| p0-alert | jira | standard | autonomous | ✅ | 2h ago | active |
| pr-stale | github | fast | notify | ✅ | never | active |
| npm-publish | local | standard | create | ❌ | — | disabled |
| weekly-standup | schedule | standard | notify | ✅ | 3d ago | silenced until 09:00 |

5. Below the table, print global config summary:
   `Global: action_level=create | cooldown=5m | fast_path=true | triggers enabled=true`

### test <name>

Dry-run a trigger against the latest inbox item that would match its `when:` conditions.

1. Load the named trigger file from `~/.xgh/triggers/<name>.yaml`.
2. Scan `~/.xgh/inbox/*.md` for items NOT in `processed/`.
3. Find the newest item matching all `when:` conditions (source, type, project, match:).
   - For `source: local` triggers: look for items with `source_type: local_command`.
   - For `source: schedule` triggers: evaluate the cron expression against now.
4. If no matching item: "No matching inbox item found for this trigger right now."
5. If found: show what would fire:
   ```
   🧪 DRY RUN — p0-alert
   Matched: ~/.xgh/inbox/2026-03-20T14-30-00Z_jira_MOBILE-1234.md
     title: "Login crash on iOS 17"
     urgency_score: 95

   Would execute 2 steps:
     Step 1 [notify/slack]: Post to #incidents — "P0: Login crash on iOS 17 — https://..."
     Step 2 [autonomous/dispatch]: /xgh-investigate "https://jira.../MOBILE-1234"
       (requires action_level: autonomous — currently allowed ✅)

   Cooldown state: never fired — would fire immediately
   ```
6. Do NOT execute any actions.

### silence <name> <duration>

Suppress a trigger temporarily.

Accepted durations: `30m`, `2h`, `1d`, etc.

1. Load `~/.xgh/triggers/.state.json` (create if missing: `{}`).
2. Calculate `silenced_until` = now + duration (ISO 8601 timestamp).
3. Write `"silenced_until": "<timestamp>"` under the trigger name in .state.json.
4. Confirm: "✅ p0-alert silenced until 2026-03-21T16:00:00Z"

### history <name>

Show the last 10 firing events for a trigger.

1. Read `.state.json` for this trigger: `last_fired`, `fire_count`, `current_cooldown_seconds`, `fired_items`.
2. Output:
   ```
   📋 p0-alert — firing history

   Total fires: 7
   Last fired: 2026-03-20T14:30:00Z (2h ago)
   Current cooldown: 20 min (exponential, base 5m, max 6h)
   Silenced: no

   Recent items fired for (last 10):
     2026-03-20T14-30-00Z_p0_jira_MOBILE-1234.md
     2026-03-19T09-15-00Z_p0_jira_MOBILE-1198.md
     2026-03-18T22-00-00Z_p0_jira_MOBILE-1156.md
   ```

## Trigger Evaluation Logic (reference)

Used by analyze and retrieve skills — documented here for consistency.

### Matching

Check all `when:` fields. ALL must match for a trigger to fire:
- `source:` — matches `item.source` field in inbox frontmatter. `*` matches any.
- `type:` — matches `item.type` from analyze classification. NOT available on fast path.
- `project:` — matches `item.project` from ingest.yaml. `*` matches any.
- `match:` — regex patterns on item frontmatter fields. `!` prefix = exclude.
- `command:` — regex matched against `command:` field (local events only).
- `exit_code:` — exact match against `exit_code:` field (local events only).
- `cron:` — matched against current time (schedule events only).

### Cooldown / backoff check

Before firing, check `.state.json` for this trigger:
1. If `silenced_until` is set and in the future → skip.
2. If `last_fired` is set: compute elapsed = now - last_fired (seconds).
3. Compute `current_cooldown_seconds` by backoff strategy:
   - `none`: 0 (always fire)
   - `fixed`: the `cooldown:` value
   - `exponential`: base_cooldown × 2^(fire_count - 1), capped at `max_cooldown`
4. If elapsed < current_cooldown_seconds → skip.
5. Check `reset_after:` — if elapsed > reset_after, reset fire_count to 0 first.

### Dedup check

Check `fired_items` array in `.state.json`. If the inbox item's filename is already
in `fired_items` → skip (prevents re-firing on the same item across cycles).

### Action level enforcement

For each `then:` step:
1. Determine step's `action_level:` (or inherit from trigger, or inherit from global default `notify`).
2. If step level > trigger `action_level:` cap → REFUSE, log warning, skip step.
3. If step level > global `action_level:` cap → REFUSE, log warning, skip step.

Level order: `notify` < `create` < `mutate` < `autonomous`

### Template variable expansion

Available in `message:`, `args:`, `title:`, `body:` fields in `then:` steps:
`{item.title}`, `{item.url}`, `{item.source}`, `{item.type}`, `{item.project}`,
`{item.author}`, `{item.timestamp}`, `{item.urgency_score}`, `{item.repo}`,
`{item.number}`, `{item.key}`, `{item.description}`, `{item.summary}`, `{item.slug}`,
`{item.version}`, `{item.severity}`, `{item.chat_id}`, `{item.channel_id}`.

In `run:` blocks: use `$ITEM_TITLE`, `$ITEM_URL`, `$ITEM_SOURCE`, `$ITEM_TYPE`,
`$ITEM_PROJECT`, `$ITEM_AUTHOR`, `$ITEM_TIMESTAMP`, `$ITEM_URGENCY`, `$ITEM_REPO`,
`$ITEM_NUMBER`, `$ITEM_KEY`, `$ITEM_VERSION`, `$ITEM_SEVERITY`.
Template `{item.*}` vars are NOT expanded in `run:` — prevents shell injection.

In `on_complete:` after a `dispatch:` step: `{result.summary}`, `{result.status}`,
`{result.files}`, `{result.commit}`, `{result.pr_url}`.

### After firing

Update `.state.json`:
```json
{
  "p0-alert": {
    "last_fired": "<ISO timestamp>",
    "fire_count": 4,
    "current_cooldown_seconds": 2400,
    "silenced_until": null,
    "fired_items": ["<filename>", "...up to 100, oldest evicted"]
  }
}
```

### Step error handling

Per-step `on_error:` (or trigger-level default):
- `continue` (default): log error, proceed to next step
- `abort`: log error, skip remaining steps
- `retry`: retry once after 5s, then continue
