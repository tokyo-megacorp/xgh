---
title: "Dogfood: claudinho tracked by xgh — verification report"
status: completed
date: 2026-03-27
owner: "xgh Team Lead"
sprint: sp2
github_issue: "#141"
---

# Dogfood Verification: claudinho tracked by xgh

## Verification results

| Check | Result | Notes |
|-------|--------|-------|
| claudinho in ingest.yaml | ✅ Pass | `projects.claudinho` exists with correct GitHub repo, sources, and intent |
| ingest.yaml structure valid | ✅ Pass | YAML parses cleanly, all required fields present |
| GitHub sources configured | ✅ Pass | `github_sources: [issues, pull_requests, releases]` |
| Retriever providers generated | ❌ Fail | `~/.xgh/providers/` is empty — no fetch.sh scripts exist for any project |
| Retrieval running | ⚠️ Partial | retrieve-all.sh fires but finds 0 providers — no actual GitHub API calls |
| Retriever log evidence | ✅ Pass | Log shows runs at session/cron intervals, but "0 providers" every time |
| Quiet hours/pause guard | ✅ Pass | Guards in retrieve-all.sh work correctly |

## Root cause: providers directory is empty

The xgh retrieve pipeline has two layers:
1. **Bash providers** (`~/.xgh/providers/*/fetch.sh`) — mode:bash scripts that call GitHub/Jira/Slack APIs
2. **MCP providers** — handled by Claude sessions via CronCreate

Neither layer has been bootstrapped for claudinho or any other project. The `/xgh-track` skill is supposed to generate provider scripts (Step 3b in track.md), but this step was not executed when claudinho was manually added to ingest.yaml.

## Issues filed

The following issues were filed based on this dogfood session:

1. **Providers not generated**: `tokyo-megacorp/xgh#145` — `/xgh-track` must generate provider scripts; manual ingest.yaml edits leave the retrieve pipeline broken. Consider adding a `/xgh-doctor` check for empty providers.

## claudinho ingest.yaml entry (for reference)

```yaml
projects:
  claudinho:
    github: [ipedro/claudinho]
    github_sources: [issues, pull_requests, releases]
    dependencies: [lcm, xgh]
    my_role: maintainer
    my_intent: >-
      Own and maintain claudinho (~/.claude) — the org brain and Claude Code
      configuration directory. Tracks agents, hooks, skills, plans, memory,
      and plugin registry.
    status: active
    providers:
      github:
        access: read
    index:
      schedule: weekly
      watch_paths: [agents/, hooks/, skills/, plans/, settings.json, CLAUDE.md]
```

## What's needed to complete dogfooding

1. Run `/xgh-track` re-onboarding for claudinho to generate provider scripts (or implement provider auto-generation from ingest.yaml)
2. Verify providers fetch claudinho issues, PRs into inbox
3. Run `/xgh-analyze` to verify claudinho context flows into LCM memory
