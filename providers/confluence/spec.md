# Confluence Provider Spec

Fetches Confluence pages recently modified by the current user. Shares Atlassian credentials with the Jira provider.

## Mode Selection

Confluence uses the same mode as Jira — if Jira is in bash mode, Confluence is too (shared credentials).

- **Bash mode** — `JIRA_EMAIL` + `JIRA_API_TOKEN` + `JIRA_BASE_URL` in `tokens.env`
- **MCP mode** — Atlassian MCP OAuth (same `atlassian` server as Jira)

Confluence has lower urgency than Jira — it is reference material, not action items.

---

## Bash Mode

### Auth

Same Atlassian credentials as Jira (`JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`).

### Connection Test

```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_BASE_URL/wiki/rest/api/space?limit=1" | jq '.results[0].name'
```

### fetch.sh Generation

**CQL:**
```
contributor = currentUser() AND lastModified >= "<cursor>"
```

**Request:**
```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_BASE_URL/wiki/rest/api/content/search?cql=<encoded_cql>&limit=10"
```

**Fields extracted:** title, space, lastModified, excerpt (truncated to 500 chars)

**Urgency:** Lower than Jira (reference material, not action items). No urgency keywords by default.

**Cursor:** ISO 8601 timestamp from `lastModified`.

### provider.yaml (bash mode)

```yaml
id: confluence
name: Confluence
auth:
  type: basic
  env:
    base_url: JIRA_BASE_URL
    email: JIRA_EMAIL
    token: JIRA_API_TOKEN
fetch:
  script: fetch.sh
  cursor_field: lastModified
  max_results: 10
inbox:
  urgency_keywords: []
```

### fetch.sh (bash mode)

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../tokens.env"

CURSOR="${CURSOR:-$(date -u -v-7d +%Y-%m-%dT%H:%M:%S.000+0000 2>/dev/null || date -u --date='7 days ago' +%Y-%m-%dT%H:%M:%S.000+0000)}"

CQL="contributor = currentUser() AND lastModified >= \"${CURSOR}\""
ENCODED_CQL=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$CQL")

curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_BASE_URL/wiki/rest/api/content/search?cql=${ENCODED_CQL}&limit=10&expand=space,history.lastUpdated,excerpt" \
  | jq '[.results[] | {
      id: .id,
      title: .title,
      space: .space.name,
      lastModified: .history.lastUpdated.when,
      excerpt: (.excerpt // "" | .[0:500])
    }]'
```

---

## MCP Mode

### Auth

Same Atlassian MCP server as Jira.

```yaml
auth:
  type: mcp_oauth
  mcp_server: atlassian
```

### Connection Test

Call the `mcp__atlassian__confluence_search` tool with `limit: 1`.

### provider.yaml (MCP mode)

```yaml
id: confluence
name: Confluence
auth:
  type: mcp_oauth
  mcp_server: atlassian
mcp:
  tools:
    - name: mcp__atlassian__confluence_search
      params_template:
        cql: "contributor = currentUser() AND lastModified >= '${CURSOR}'"
        limit: 10
  result_mapping:
    items: ".results"
    timestamp: ".lastModified"
    text: ".title"
inbox:
  urgency_keywords: []
```
