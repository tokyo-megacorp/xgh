---
name: xgh:doctor
description: >
  Pipeline health check. Validates config completeness, Slack/Jira/lossless-claude
  connectivity, scheduler freshness, workspace stats, and codebase index status.
  Outputs a structured ✓/✗ report with fix suggestions.
type: rigid
triggers:
  - when the user runs /xgh-doctor
  - when the user says "check ingest", "health check", "is the pipeline running"
---

# xgh:doctor — Pipeline Health Check

Run all checks and output a structured report. Use `✓` for pass, `✗` for fail.

## Check 1 — Config

- `~/.xgh/ingest.yaml` exists and parses: `python3 -c "import yaml; yaml.safe_load(open('...'))" 2>&1`
- Required fields present: `profile.name`, `profile.slack_id`, `profile.platforms`
- At least one active project under `projects:`
- lossless-claude is configured (check `.claude/.mcp.json` has `lossless-claude` entry)

## Check 2 — Connectivity

For each active project:
- Each Slack channel: `slack_search_channels` to verify accessible
- Each Jira key: `getJiraIssue` with a simple query to verify it resolves

**Model server checks:** Read `XGH_BACKEND` from `~/.xgh/models.env` (source the file via Bash).
- If `XGH_BACKEND=remote`: skip local model server checks (no vllm-mlx / ollama service to verify);
  instead run the remote server reachability check below.
- If `XGH_BACKEND=vllm-mlx` or `XGH_BACKEND=ollama` (or unset): run the local model server check
  (`curl -sf http://localhost:11434/v1/models`) as normal.

**Remote inference server check** (only when `XGH_BACKEND=remote`):
Read `XGH_REMOTE_URL` from `~/.xgh/models.env`, then:
```bash
curl -sf --max-time 5 "${XGH_REMOTE_URL}/v1/models"
```
- If reachable: parse the JSON response and count models (`jq '.data | length'` or Python).
  Report: `✓ ${XGH_REMOTE_URL} — reachable, N models available`
- If unreachable (non-zero exit / timeout): report:
  ```
  ✗ ${XGH_REMOTE_URL} — unreachable (timeout)
    Fix: ensure the server is running and port is accessible from this machine
  ```

Qdrant: `curl -sf http://localhost:6333/healthz` via Bash

If Qdrant fails, run deeper diagnosis:
```bash
# Check launchd status
launchctl list | grep qdrant
# Check for crash reason
tail -20 /tmp/qdrant.log 2>/dev/null | grep -E "ERROR|WARN|Panic"
tail -5 /tmp/qdrant.error.log 2>/dev/null
```

Common Qdrant failures and fixes:
| Error | Fix |
|---|---|
| `WouldBlock` / WAL lock (exit 101) | `pkill -f qdrant; rm -f ~/.qdrant/storage/storage/collections/*/0/wal/open-*; launchctl load ~/Library/LaunchAgents/com.qdrant.server.plist` |
| `jemalloc: background_thread` (warning only) | Add `MALLOC_CONF=background_thread:false` to the plist EnvironmentVariables (cosmetic, not the crash cause) |
| Missing plist | Re-run `scripts/ingest-schedule.sh install` |
| Binary missing | `brew install qdrant` or download to `~/.qdrant/bin/qdrant` |

lossless-claude MCP availability: check if `mcp__lossless-claude__lcm_search` is present in the available tool list:
- Tool absent → lossless-claude MCP not registered. Fix: add lossless-claude entry to `.claude/.mcp.json`
- Tool present but call returns error → daemon not running. Fix: `lossless-claude daemon start`

**Important:** lossless-claude MCP availability is determined by whether `mcp__lossless-claude__lcm_search` appears in the tool list, NOT by file presence on disk.

## Check 3 — Pipeline freshness

Check `~/.xgh/logs/retriever.log` for last timestamp (last line matching ISO date):
- < 10 min ago: ✓ healthy
- 10–30 min ago: ⚠ warn
- > 30 min ago: ✗ overdue

Check `~/.xgh/logs/analyzer.log` similarly:
- < 45 min: ✓ | 45–90 min: ⚠ | > 90 min: ✗

## Check 4 — Scheduler

Call CronList. Find jobs where prompt is `/xgh-retrieve` or `/xgh-analyze`.

Also check `XGH_SCHEDULER` in the environment:
```bash
python3 -c "import os; print(os.environ.get('XGH_SCHEDULER', 'not set'))"
```

Report each job found:
- Job present → `✓ retrieve: active (*/5 * * * *)` / `✓ analyze: active (*/30 * * * *)`
- Job missing → `✗ retrieve: not scheduled` / `✗ analyze: not scheduled`
- `XGH_SCHEDULER=on` set → `✓ XGH_SCHEDULER=on (jobs will auto-register each session)`
- `XGH_SCHEDULER` not set → `⚠ XGH_SCHEDULER not set — jobs won't persist across sessions`

**Fix (if jobs missing):** Run `/xgh-schedule resume` to register jobs now.
**Fix (if XGH_SCHEDULER not set):** `echo 'export XGH_SCHEDULER=on' >> ~/.zshrc && source ~/.zshrc`

## Check 5 — Workspace stats

Query Qdrant collection stats:
```bash
curl -sf "${QDRANT_URL}/collections/${WORKSPACE_COLLECTION}"
```
Show: exists ✓/✗, vector count, approximate size.

## Check 6 — Codebase index

For each project with `github:` entries, check `index.last_full` against `index.schedule`:
- Never indexed: ✗ (suggest `/xgh-index`)
- Overdue per schedule: ⚠
- Current: ✓

## Output format

```
xgh Ingest Health Check
═══════════════════════

Config
  ✓ ~/.xgh/ingest.yaml exists and parses
  ✓ Profile: [name] ([role], [squad])
  ✓ 2 active projects configured

Connectivity
  ✓ Slack: #channel-1 accessible
  ✗ Slack: #channel-missing — not found (check channel name in ingest.yaml)
  ✓ Jira: PTECH-31204 exists (23 open issues)
  ✓ Qdrant: localhost:6333 responding
  ✓ lossless-claude: connected (tool available)
  # Remote inference (when XGH_BACKEND=remote):
  ✓ Remote inference server: http://macmini.local:11434 — reachable, 2 models available
  # OR if unreachable:
  ✗ Remote inference server: http://192.168.1.100:11434 — unreachable (timeout)
    Fix: ensure the server is running and port 11434 is accessible from this machine
  # OR if issues:
  ✗ Qdrant: not responding — WAL lock detected
    Fix: pkill -f qdrant && rm -f ~/.qdrant/storage/storage/collections/*/0/wal/open-* && launchctl load ~/Library/LaunchAgents/com.qdrant.server.plist
  ✗ lossless-claude: not in tool list — add to .claude/.mcp.json (command: lossless-claude, args: [mcp])

Pipeline
  ✓ Retriever: last run 3 min ago (healthy)
  ✗ Analyzer: last run 52 min ago (overdue — threshold: 45 min)

Scheduler
  ✓ XGH_SCHEDULER=on (jobs auto-register each session)
  ✓ retrieve: active (*/5 * * * *)
  ✓ analyze: active (*/30 * * * *)
  # OR if not configured:
  ⚠ XGH_SCHEDULER not set — jobs won't persist across sessions
  ✗ retrieve: not scheduled
  ✗ analyze: not scheduled
    Fix: /xgh-schedule resume  (now) | export XGH_SCHEDULER=on >> ~/.zshrc  (persistent)

Workspace
  ✓ Collection "xgh-workspace" exists (142 vectors)

Codebase Index
  ✓ acme-ios: indexed 2 days ago (schedule: weekly — OK)
  ✗ passcode-service: never indexed — run /xgh-index

Summary: 9 passed, 0 warnings, 2 failures
Fix: Check #channel-missing name. Run: claude -p "/xgh-analyze" to clear overdue analyzer.
```
