# GitHub Provider Spec

> Instructions for Claude when generating `provider.yaml` and `fetch.sh` for a project
> with `github:` sources. Read during `/xgh-track` setup and `/xgh-retrieve` runs.

---

## No user questions needed

GitHub auth is handled entirely by the `gh` CLI, which must already be authenticated
(`gh auth status`). No API tokens, no `tokens.env` file, no OAuth flow needed.

---

## `provider.yaml` generation

When a project in `ingest.yaml` has `github:` or `github_sources:` fields, generate
`providers/github/provider.yaml` with the following structure:

```yaml
name: github
mode: bash
auth:
  type: cli
  tool: gh
sources:
  # Populated from all active projects' github: and github_sources: fields
  - repo: owner/repo
    sources: [pull_requests, issues, notifications]  # subset relevant to project
    watch_prs: []          # optional: PR numbers to always fetch regardless of cursor
    releases: false        # set true if releases in github_sources
```

Rules:
- `mode` is always `bash` — there is no MCP mode for GitHub.
- Deduplicate repos across projects.
- If a project specifies `github_sources: [releases]`, set `releases: true` for that repo.
- If a project specifies `watch_prs: [42, 99]`, populate `watch_prs` accordingly.

---

## `fetch.sh` generation instructions

Generate `providers/github/fetch.sh` as an executable bash script. The script:

1. Sources `$XGH_DIR/providers/github/provider.yaml` values (or reads them via yq).
2. Reads/writes the cursor from `$XGH_DIR/providers/github/.cursor`.
3. Writes one `.md` inbox item per result to `$XGH_DIR/inbox/`.

### Notifications

```bash
gh api /notifications --jq '.[] | select(.unread == true) | {id: .id, title: .subject.title, type: .subject.type, repo: .repository.full_name, url: .subject.url, updated_at: .updated_at}'
```

Emit one inbox item per unread notification.

### Pull requests (per repo)

```bash
gh pr list --repo <repo> \
  --json number,title,author,state,reviewDecision,updatedAt \
  --limit 20 \
  --search "updated:>$CURSOR"
```

Also run for awaiting-reply detection:

```bash
gh pr list --repo <repo> --review-requested @me \
  --json number,title,author,state,reviewDecision,updatedAt
```

### Issues (per repo)

```bash
gh issue list --repo <repo> \
  --json number,title,author,state,labels,updatedAt \
  --limit 10 \
  --search "updated:>$CURSOR"
```

### Releases (per repo, only if `releases: true`)

```bash
gh release list --repo <repo> --limit 3
```

### `watch_prs` (always fetched, ignores cursor)

For each PR number listed in `watch_prs`:

```bash
gh pr view <number> --repo <repo> \
  --json number,title,author,state,reviewDecision,updatedAt,body
```

---

## Cursor strategy

- Format: ISO 8601 timestamp (e.g., `2026-03-20T00:00:00Z`)
- Default when no cursor exists: 24 hours ago (`date -u -v-24H +%Y-%m-%dT%H:%M:%SZ`)
- After a successful fetch, update cursor to current UTC time.
- All `gh` list commands use `--search "updated:>$CURSOR"` to filter.
- `watch_prs` entries are always fetched regardless of cursor.

---

## Urgency scoring

After fetching, score each item by checking its `title` and `labels` against the
project's `urgency_keywords` list (from `ingest.yaml`). Add `urgency_score` to the
inbox item frontmatter. Higher score = more urgent.

---

## Inbox item format

Each fetch produces one `.md` file in `$XGH_DIR/inbox/` per item:

```markdown
---
type: inbox_item
source_type: github_pr        # github_pr | github_issue | github_notification | github_release
source_repo: owner/repo
source_ts: 2026-03-20T10:00:00Z
project: project_name
urgency_score: 30
processed: false
---

PR #42: Fix authentication timeout
Author: contributor
Updated: 2026-03-20T10:00:00Z
Status: open
Review: CHANGES_REQUESTED
```

Filename convention: `github_<repo_slug>_<type>_<number>_<timestamp>.md`
