# Provider Spec — `_template`

> **Purpose:** This document is the instruction manual Claude reads when scaffolding an unknown provider
> via `/xgh-track add-provider <name>`. Follow every section in order. Do not skip sections.
> Generated artifacts land in `~/.xgh/providers/<name>/` at runtime; inbox items land in `~/.xgh/inbox/`.

---

## Section 1 — Questions to Ask the User

Ask the following six questions before generating any files. Collect all answers before proceeding.

1. **Provider name** — What is the short slug for this provider? (e.g. `github`, `linear`, `pagerduty`)
   - Must be lowercase, alphanumeric, hyphens allowed. No spaces.

2. **Base API URL** — What is the base URL for the provider's REST API?
   - Example: `https://api.github.com` or `https://yourorg.atlassian.net/rest/api/3`
   - Leave blank if this provider is MCP-only.

3. **Authentication method** — Do you have an API token or CLI tool, or does this service authenticate only via MCP/OAuth?
   - Answer **A**: "I have an API token" → proceed with `mode: bash`
   - Answer **B**: "I use a CLI tool (e.g. `gh`, `gcloud`)" → proceed with `mode: bash`, `auth.type: cli`
   - Answer **C**: "Only MCP / OAuth / SSO — no personal token" → proceed with `mode: mcp`

4. **Token or MCP details** *(answer depends on Q3)*:
   - If **bash / API token**: What environment variable name should hold the token? (e.g. `GITHUB_TOKEN`, `LINEAR_API_KEY`)
     - For basic auth (username + password) provide two variable names.
   - If **bash / CLI tool**: What is the CLI tool name? (e.g. `gh`, `gcloud`, `op`)
   - If **mcp**: What is the MCP server name configured in `.claude/.mcp.json`? (e.g. `github`, `linear`)

5. **Notifications / recent-activity endpoint or MCP tool** — How do you fetch recent activity or notifications?
   - If **bash**: Provide the endpoint path (e.g. `/notifications`, `/issues?filter=assigned&state=open`)
     Also provide the `jq` path that extracts the list of items from the response (e.g. `.[]`, `.issues[]`).
   - If **mcp**: Provide the MCP tool name to call (e.g. `list_issues`, `get_notifications`) and the parameter
     template (key/value pairs, use `${SOURCE_ID}` for the project identifier and `${CURSOR}` for the cursor).

6. **Cursor strategy** — How should xgh track "what was already fetched"?
   - `timestamp` — filter by a date/time field (most common). What format? `iso8601` / `unix` / `snowflake`
   - `id` — store the last-seen ID and fetch items newer than it
   - `page_token` — use a continuation/page token returned by the API

7. **Urgency keywords** — Provide domain-specific keywords that indicate high urgency for this provider.
   - Defaults if none provided: `critical`, `blocker`, `urgent`, `incident`, `outage`, `sev1`, `p0`
   - Examples for GitHub: `security`, `CVE`, `breaking change`
   - Examples for PagerDuty: `triggered`, `acknowledged`, `high`

---

## Section 2 — Mode Decision Logic

After collecting answers, determine the mode:

| User answer | `mode` value | `auth.type` |
|-------------|-------------|-------------|
| API token (bearer) | `bash` | `bearer` |
| API token (header key) | `bash` | `api_key` |
| API token (basic auth) | `bash` | `basic` |
| CLI tool | `bash` | `cli` |
| MCP / OAuth / SSO | `mcp` | `mcp_oauth` |

**bash mode** → generate both `provider.yaml` and `fetch.sh`.
**mcp mode** → generate `provider.yaml` only (with `mcp:` section). No `fetch.sh` needed; xgh calls MCP tools directly.

---

## Section 3 — `provider.yaml` Generation Instructions

Create `~/.xgh/providers/<name>/provider.yaml` using the schema below. Fill in every field from the user's answers.
Omit the `mcp:` section entirely for `bash` mode. Omit `fetch.sh`-specific auth fields (`env_var`, `tool`) for `mcp` mode.

```yaml
name: <provider_name>               # from Q1
version: 1
mode: bash                          # bash | mcp (from Section 2)
auth:
  type: bearer                      # cli | bearer | basic | api_key | mcp_oauth | none
  tool: null                        # CLI tool name if auth.type is cli; otherwise null
  env_var: null                     # token env var (bearer/api_key/basic username); null for mcp
  env_var_2: null                   # second env var for basic auth password; null otherwise
  mcp_server: null                  # MCP server name if mode is mcp; otherwise null
sources:
  - project: <project_name>         # human-readable label chosen by user
    id: <source_identifier>         # repo slug, org name, workspace ID, etc.
    watch:
      - notifications               # resource types: notifications | issues | prs | alerts | etc.
cursor:
  strategy: timestamp               # timestamp | id | page_token (from Q6)
  format: iso8601                   # iso8601 | unix | snowflake
inbox:
  source_type: <prefix>             # short prefix used in inbox filenames, e.g. "gh", "linear"
  urgency_keywords:                 # from Q7
    - critical
    - blocker
    - urgent
    - incident
    - outage
    - sev1
    - p0
# mcp section — ONLY include when mode: mcp
mcp:
  tools:
    - name: <mcp_tool_name>         # from Q5
      params_template:
        project: "${SOURCE_ID}"     # ${SOURCE_ID} → replaced with sources[].id at runtime
        since: "${CURSOR}"          # ${CURSOR} → replaced with cursor value at runtime
  result_mapping:
    items: ".items[]"               # jq-style path to the array of items in the MCP response
    timestamp: ".updated_at"        # path to the timestamp field on each item
    text: ".title"                  # path to the primary text field
    author: ".author.login"         # path to the author field
```

**Checklist before saving provider.yaml:**
- [ ] `name` matches the slug from Q1
- [ ] `mode` is either `bash` or `mcp`, not both
- [ ] `auth.env_var` is set for bash/token modes; null for mcp mode
- [ ] `auth.mcp_server` is set for mcp mode; null for bash mode
- [ ] `cursor.strategy` and `cursor.format` reflect the user's answer to Q6
- [ ] `inbox.urgency_keywords` includes the user's domain-specific keywords from Q7
- [ ] `mcp:` section is present only when `mode: mcp`

---

## Section 4 — `fetch.sh` Generation Instructions (bash mode only)

Skip this section entirely if `mode: mcp`.

Create `~/.xgh/providers/<name>/fetch.sh` using the template below. Replace all `<placeholders>`.

```bash
#!/usr/bin/env bash
# fetch.sh — <provider_name> provider for xgh
# Auto-generated by /xgh-track add-provider. Edit as needed.
set -euo pipefail

PROVIDER="<provider_name>"
XGH_DIR="${XGH_DIR:-$HOME/.xgh}"
PROVIDER_DIR="$XGH_DIR/providers/$PROVIDER"
INBOX_DIR="$XGH_DIR/inbox"
LOG_FILE="$XGH_DIR/logs/provider-${PROVIDER}.log"
CURSOR_FILE="$PROVIDER_DIR/cursor"

mkdir -p "$INBOX_DIR" "$XGH_DIR/logs"

# ── Logging ────────────────────────────────────────────────────────────────
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$PROVIDER] $*" | tee -a "$LOG_FILE"; }

# ── Load tokens.env ────────────────────────────────────────────────────────
# shellcheck source=/dev/null
[ -f "$XGH_DIR/tokens.env" ] && source "$XGH_DIR/tokens.env"

# ── Parse provider.yaml (no python dependency) ────────────────────────────
yaml_get() { grep -m1 "^  $1:" "$PROVIDER_DIR/provider.yaml" 2>/dev/null | awk -F': ' '{print $2}' | tr -d '"'"'"' '; }
SOURCE_ID="$(grep -A2 '^\s*-\s*project:' "$PROVIDER_DIR/provider.yaml" | grep 'id:' | head -1 | awk -F': ' '{print $2}' | tr -d '"'"'"' ')"

# ── Read cursor (default: 24 hours ago) ───────────────────────────────────
if [ -f "$CURSOR_FILE" ]; then
  CURSOR="$(cat "$CURSOR_FILE")"
else
  # iso8601 default — adjust format string for unix/snowflake strategies
  CURSOR="$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='24 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
fi

log "Fetching since cursor=$CURSOR source=$SOURCE_ID"

# ── API call ───────────────────────────────────────────────────────────────
# Replace <BASE_URL>, <ENDPOINT>, and auth header style as needed.
RESPONSE="$(curl -sf \
  -H "Authorization: Bearer ${<ENV_VAR>}" \
  -H "Accept: application/json" \
  "<BASE_URL><ENDPOINT>?since=${CURSOR}" \
)" || { log "ERROR: curl failed (exit $?)"; exit 1; }

# ── Extract items ──────────────────────────────────────────────────────────
# Adjust the jq filter to match the actual response shape.
ITEMS="$(echo "$RESPONSE" | jq -c '<JQ_ITEMS_PATH>' 2>/dev/null)" || { log "ERROR: jq parse failed"; exit 1; }

COUNT=0
NEW_CURSOR="$CURSOR"

# ── Write inbox items ──────────────────────────────────────────────────────
while IFS= read -r item; do
  [ -z "$item" ] && continue

  # Extract fields — adjust jq paths to match the provider's response shape
  ITEM_ID="$(echo "$item"    | jq -r '.id // .number // .key // "unknown"')"
  ITEM_TS="$(echo "$item"    | jq -r '.updated_at // .created_at // .timestamp // ""')"
  ITEM_TEXT="$(echo "$item"  | jq -r '.title // .subject // .text // "No title"')"
  ITEM_URL="$(echo "$item"   | jq -r '.html_url // .url // .web_url // ""')"
  ITEM_AUTHOR="$(echo "$item" | jq -r '.user.login // .author.name // .reporter.displayName // "unknown"')"

  INBOX_FILE="$INBOX_DIR/${PROVIDER}-${ITEM_ID}.md"

  # Skip if already exists (idempotent)
  [ -f "$INBOX_FILE" ] && continue

  cat > "$INBOX_FILE" <<EOF
---
type: inbox_item
source_type: <SOURCE_TYPE_PREFIX>
source_repo: ${SOURCE_ID}
source_ts: ${ITEM_TS}
project: <project_name>
urgency_score: 0
processed: false
---

${ITEM_TEXT}
url: ${ITEM_URL}
author: ${ITEM_AUTHOR}
EOF

  # Track newest cursor value
  if [ -n "$ITEM_TS" ] && [[ "$ITEM_TS" > "$NEW_CURSOR" ]]; then
    NEW_CURSOR="$ITEM_TS"
  fi

  COUNT=$((COUNT + 1))
done <<< "$ITEMS"

# ── Update cursor atomically ───────────────────────────────────────────────
if [ "$NEW_CURSOR" != "$CURSOR" ]; then
  TMP="$(mktemp)"
  echo "$NEW_CURSOR" > "$TMP"
  mv "$TMP" "$CURSOR_FILE"
  log "Cursor advanced to $NEW_CURSOR"
fi

log "Done. Wrote $COUNT new inbox items."
```

**After generating fetch.sh:**
- Run `chmod +x ~/.xgh/providers/<name>/fetch.sh`
- Tell the user to add their token to `~/.xgh/tokens.env` (see Section 6)
- Run the connection test in Section 7

---

## Section 5 — MCP Fetch Instructions (mcp mode only)

Skip this section entirely if `mode: bash`.

For `mcp` mode, xgh calls the MCP tools directly using the `mcp:` section in `provider.yaml`.
No `fetch.sh` is generated. The `mcp:` block must contain:

```yaml
mcp:
  tools:
    - name: <mcp_tool_name>
      params_template:
        # Map provider.yaml source fields to MCP tool parameters.
        # Use ${SOURCE_ID} as a placeholder for sources[].id at runtime.
        # Use ${CURSOR} as a placeholder for the current cursor value.
        # Example for a GitHub MCP tool:
        owner: "${SOURCE_ID}"
        state: "open"
        since: "${CURSOR}"
  result_mapping:
    # jq-style paths into the MCP tool's response object
    items: ".items[]"         # path to the array of result items
    timestamp: ".updated_at"  # timestamp field used to advance the cursor
    text: ".title"            # primary human-readable text
    author: ".author.login"   # attribution field
```

Ask the user to verify that the MCP server name matches the key in their `.claude/.mcp.json` file.
The MCP server must already be configured and authenticated before xgh can use it.

---

## Section 6 — `tokens.env` Instructions (bash mode only)

Skip this section if `mode: mcp`.

Instruct the user to add their token to `~/.xgh/tokens.env`:

```bash
# ~/.xgh/tokens.env
# Source this file in fetch.sh to load provider tokens.
# DO NOT commit this file to version control.

<ENV_VAR>=your_token_here
# For basic auth, also add:
# <ENV_VAR_2>=your_password_here
```

Create the file with secure permissions if it does not exist:

```bash
touch ~/.xgh/tokens.env && chmod 600 ~/.xgh/tokens.env
```

---

## Section 7 — Connection Test

Verify authentication works before finishing setup.

**bash mode (bearer/api_key):**
```bash
source ~/.xgh/tokens.env
curl -sf -H "Authorization: Bearer ${<ENV_VAR>}" "<BASE_URL>/user" | jq .
# Expected: 200 OK with your user profile JSON
```

**bash mode (CLI tool):**
```bash
<CLI_TOOL> auth status
# Expected: authenticated / logged in
```

**mcp mode:**
Call the MCP tool with a minimal parameter set and confirm it returns data without an auth error:
```
Use MCP tool <mcp_tool_name> with params: { "<key>": "<minimal_value>" }
Expected: non-empty result, no 401/403 error
```

If the connection test fails, help the user debug before proceeding.

---

## Section 8 — Urgency Keywords

Default urgency keywords for new providers (use these if the user provides none in Q7):

```yaml
urgency_keywords:
  - critical
  - blocker
  - urgent
  - incident
  - outage
  - sev1
  - p0
```

Merge user-provided keywords with the defaults — do not replace, append.
All keywords are matched case-insensitively against the inbox item text when computing `urgency_score`.

---

## Reference — Provider Contract Summary

| Artifact | Path | Required for |
|----------|------|-------------|
| `provider.yaml` | `~/.xgh/providers/<name>/provider.yaml` | Both modes |
| `fetch.sh` | `~/.xgh/providers/<name>/fetch.sh` | `bash` mode only |
| `tokens.env` | `~/.xgh/tokens.env` | `bash` mode only |
| `cursor` | `~/.xgh/providers/<name>/cursor` | Both modes (auto-created) |
| `inbox` items | `~/.xgh/inbox/<name>-<id>.md` | Both modes (auto-created) |

**Inbox item frontmatter fields:** `type`, `source_type`, `source_repo`, `source_ts`, `project`, `urgency_score`, `processed`

**Cursor strategies:** `timestamp` (iso8601/unix/snowflake) · `id` · `page_token`

**Auth types:** `bearer` · `api_key` · `basic` · `cli` · `mcp_oauth` · `none`
