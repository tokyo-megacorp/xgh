---
description: "Internal repair-path skill — invoked when the user runs /xgh-init-providers, asks to 'regenerate providers', 'fix empty providers', 'providers directory is empty', or after manually editing ingest.yaml without running /xgh-track. Reads ingest.yaml and generates provider scripts in ~/.xgh/user_providers/ for all projects with github access. Not user-facing: use /xgh-init-providers command instead."
---

# xgh:init-providers — Generate Provider Scripts from ingest.yaml

Reads `~/.xgh/ingest.yaml` and generates or updates `provider.yaml` + `fetch.sh` in
`~/.xgh/user_providers/` for all services currently in ingest.yaml. This is the
repair path when providers were not generated (e.g., after a manual ingest.yaml edit
that bypassed `/xgh-track` Step 3b).

> **Persistence guarantee:** Only creates or updates providers for services explicitly
> in ingest.yaml. Never deletes existing providers. If a provider already exists,
> skip it (unless `--force` flag is passed).

## Step 1 — Read ingest.yaml

Parse `~/.xgh/ingest.yaml` and collect:

```python
import yaml
data = yaml.safe_load(open(os.path.expanduser('~/.xgh/ingest.yaml')))
projects = data.get('projects', {})

# For each project with providers.github:
github_repos = {}  # project_name -> {repos: [], sources: []}
for project_name, project in projects.items():
    if project.get('providers', {}).get('github'):
        repos = project.get('github', [])
        sources = project.get('github_sources', ['issues', 'pull_requests', 'releases', 'security_alerts', 'dependabot'])
        if repos:
            github_repos[project_name] = {'repos': repos, 'sources': sources}
```

## Step 2 — Check existing providers

```bash
ls ~/.xgh/user_providers/ 2>/dev/null
```

For each service found:
- Report: `⚠ provider already exists: <name> — skipping (use --force to overwrite)`

## Step 3 — Generate github-cli provider

If any projects have `providers.github` configured and `~/.xgh/user_providers/github-cli/` does
not exist (or `--force` was passed):

**Probe mode:**
```bash
command -v gh && gh auth status
```
- `gh` available and authenticated → use `mode: cli`
- Otherwise → report error and suggest `gh auth login`

**Generate `~/.xgh/user_providers/github-cli/provider.yaml`:**

```yaml
service: github
mode: cli
cursor_strategy: timestamp
description: Fetches GitHub issues, pull requests, releases, security alerts, and Dependabot alerts for all tracked repos using gh CLI

sources:
  - project: <project_name>
    repo: <github_repo>
    types: <github_sources filtered to [issues, pull_requests, releases, security_alerts, dependabot]>
  # ... one entry per project with github repos
```

**Generate `~/.xgh/user_providers/github-cli/fetch.sh`:**

The script must:
1. Read `CURSOR_FILE` env var for incremental pagination (ISO timestamp)
2. Default to 24h ago if no cursor exists
3. For each repo in the provider, based on the configured `types`, run:
   - `issues` → `gh issue list --json` filtered by `updatedAt > SINCE`
   - `pull_requests` → `gh pr list --json` filtered by `updatedAt > SINCE`
   - `releases` → `gh release list --json` filtered by `createdAt > SINCE`
   - `security_alerts` → `gh api /repos/$OWNER/$REPO/dependabot/alerts --jq '.[] | select(.updated_at > $SINCE)'`
   - `dependabot` → `gh api /repos/$OWNER/$REPO/vulnerability-alerts` (returns enabled/disabled status; for per-alert data use `security_alerts`)
4. Write each result to `$INBOX_DIR/<timestamp>_github_<repo_slug>_<type><number>.md`
   with frontmatter:
   ```
   ---
   type: inbox_item
   source_type: github_<issue|pr|release|security_alert|dependabot>
   source_repo: <owner/repo>
   source_ts: <updatedAt or updated_at>
   project: <project_name>
   urgency_score: 50
   processed: false
   awaiting_direction: null
   links_followed: []
   ---
   ```
5. Skip files that already exist in inbox (idempotent)
6. Write `NEW_CURSOR` to `$CURSOR_FILE` on success
7. Exit 0 on success, exit 1 on fatal errors, exit 2 on partial success

Make `fetch.sh` executable: `chmod +x fetch.sh`

## Step 4 — Validate

Run the generated fetch.sh with a recent cursor:

```bash
CURSOR_FILE="/tmp/xgh_validate_cursor" \
INBOX_DIR="$HOME/.xgh/inbox" \
PROVIDER_DIR="$HOME/.xgh/user_providers/github-cli" \
TOKENS_FILE="$HOME/.xgh/tokens.env" \
bash "$HOME/.xgh/user_providers/github-cli/fetch.sh"
```

- Exit 0: report success + number of items fetched
- Non-zero: show stderr, offer to retry or skip

## Step 5 — Report

```
xgh init-providers
══════════════════

GitHub
  ✓ github-cli created — N repos, cli mode
    Repos: owner/repo1, owner/repo2, ...
    Validated: fetched M items

Summary: 1 provider created. Run /xgh-doctor to verify pipeline health.
```

If `user_providers/` was already populated with a valid github-cli provider:
```
  ⚠ github-cli already exists — skipping. Use /xgh-init-providers --force to regenerate.
```
