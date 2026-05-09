# hooks/ — Lifecycle Hook Scripts

6 hook scripts that extend xgh session behavior. Hooks are shell scripts invoked by Claude Code lifecycle events.

## Hooks

| Script | Lifecycle Event | Role |
|---|---|---|
| `session-start.sh` | SessionStart | Initializes xgh session: loads context tree, checks provider health, injects briefing |
| `session-start-preferences.sh` | SessionStart | Loads per-project preferences from YAML config into session context |
| `post-tool-use.sh` | PostToolUse | Tracks tool usage, updates context tree on significant edits |
| `post-compact-preferences.sh` | PostCompact | Rebuilds preference index after context compaction |
| `pre-tool-use-preferences.sh` | PreToolUse | Injects relevant preferences before tool execution |
| `_pref-index-builder.sh` | (internal) | Shared helper: builds the preference index from YAML — not invoked directly by CC lifecycle |

## Invariants

- Hook scripts must be idempotent — they fire multiple times per session
- No hook may block execution (fail silently on non-critical errors)
- `_pref-index-builder.sh` is an internal helper; do not register it as a hook in settings
- Preference hooks (`*-preferences.sh`) read from `config/preferences.yaml` via `lib/preferences.sh`

## Adding a Hook

1. Write `hooks/<name>.sh` following the fail-silent pattern
2. Register in `.claude/settings.json` under the correct lifecycle key
3. Add to the table above
4. Run `bash tests/test-hooks.sh` and `bash tests/test-hook-ordering.sh` to verify
