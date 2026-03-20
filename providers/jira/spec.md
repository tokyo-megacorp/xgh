# Jira Provider Spec

Fetches Jira issues assigned to the current user, filtered by project and updated timestamp.

## Mode Selection

> "Do you have a Jira API token, or is Jira connected via Atlassian MCP/OAuth?"

- **Bash mode** — API token in `tokens.env`
- **MCP mode** — Atlassian MCP OAuth

---

## Bash Mode

### Auth

Basic auth using `JIRA_EMAIL` and `JIRA_API_TOKEN`. Base URL: `JIRA_BASE_URL`.

Add to `tokens.env`:

```bash
JIRA_BASE_URL=https://your-org.atlassian.net
JIRA_EMAIL=you@example.com
JIRA_API_TOKEN=your_api_token_here
```

### Connection Test

```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" "$JIRA_BASE_URL/rest/api/3/myself" | jq .displayName
```

### fetch.sh Generation

**JQL:**
```
assignee = currentUser() AND project = <KEY> AND updated >= "<cursor>" ORDER BY updated DESC
```

**Request:**
```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_BASE_URL/rest/api/3/search?jql=<encoded_jql>&maxResults=20"
```

**Fields extracted:** key, summary, status, assignee, priority, updated

**Urgency scoring:**
- Blocker → 90
- Critical → 80
- Major → 60

**Cursor:** ISO 8601 timestamp from most recent `updated` field.

### provider.yaml (bash mode)

```yaml
id: jira
name: Jira
auth:
  type: basic
  env:
    base_url: JIRA_BASE_URL
    email: JIRA_EMAIL
    token: JIRA_API_TOKEN
fetch:
  script: fetch.sh
  cursor_field: updated
  max_results: 20
inbox:
  urgency_keywords:
    - blocker
    - critical
    - major
```

### fetch.sh (bash mode)

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../tokens.env"

PROJECT="${SOURCE_ID:-}"
CURSOR="${CURSOR:-$(date -u -v-7d +%Y-%m-%dT%H:%M:%S.000+0000 2>/dev/null || date -u --date='7 days ago' +%Y-%m-%dT%H:%M:%S.000+0000)}"

JQL="assignee = currentUser() AND project = ${PROJECT} AND updated >= \"${CURSOR}\" ORDER BY updated DESC"
ENCODED_JQL=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$JQL")

curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_BASE_URL/rest/api/3/search?jql=${ENCODED_JQL}&maxResults=20" \
  | jq '[.issues[] | {
      id: .key,
      title: .fields.summary,
      status: .fields.status.name,
      assignee: .fields.assignee.displayName,
      priority: .fields.priority.name,
      updated: .fields.updated
    }]'
```

---

## MCP Mode

### Auth

Atlassian MCP OAuth. No API token required.

```yaml
auth:
  type: mcp_oauth
  mcp_server: atlassian
```

### Connection Test

Call the `mcp__atlassian__jira_search` tool with a simple JQL query (e.g., `assignee = currentUser() ORDER BY updated DESC`) and `maxResults: 1`.

### provider.yaml (MCP mode)

```yaml
id: jira
name: Jira
auth:
  type: mcp_oauth
  mcp_server: atlassian
mcp:
  tools:
    - name: mcp__atlassian__jira_search
      params_template:
        jql: "assignee = currentUser() AND project = ${SOURCE_ID} AND updated >= '${CURSOR}'"
        maxResults: 20
  result_mapping:
    items: ".issues"
    timestamp: ".fields.updated"
    text: ".fields.summary"
    author: ".fields.assignee.displayName"
inbox:
  urgency_keywords:
    - blocker
    - critical
    - major
```
