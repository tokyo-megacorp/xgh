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
> **Context-mode:** Use `ctx_execute_file` for analysis reads; `Read` only for files you will
> Edit within 1-2 tool calls. Use `ctx_batch_execute` for multi-command research. Full routing
> rules: `references/context-mode-routing.md`


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

## Check 3b — Context Efficiency

Run both subsections in parallel.

### RTK — output compression

Instruct the agent to run these checks via `ctx_execute` (or Bash if ctx_execute unavailable):

```bash
RTK_BIN=$(command -v rtk 2>/dev/null || echo "${HOME}/.local/bin/rtk")
if [ -x "$RTK_BIN" ]; then
  echo "binary_found=true"
  echo "binary_path=$RTK_BIN"
  "$RTK_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 | xargs -I{} echo "version={}"
  "$RTK_BIN" gain --json 2>/dev/null || echo "gain_unavailable=true"
else
  echo "binary_found=false"
fi
```

Check hook registration:

```bash
python3 -c "
import json, os
for f in [os.path.expanduser('~/.claude/settings.json'),
          '.claude/settings.local.json']:
    if os.path.isfile(f):
        d = json.load(open(f))
        for e in d.get('hooks',{}).get('PreToolUse',[]):
            for h in e.get('hooks',[]):
                if 'rtk' in h.get('command','') and 'hook' in h.get('command',''):
                    print('hook_registered=true')
                    print('hook_command=' + h['command'])
                    exit(0)
print('hook_registered=false')
"
```

Format output as:

```
#### RTK — output compression
| Metric          | Value                                         |
|-----------------|-----------------------------------------------|
| Version         | v{version} {status}                           |
| Binary          | {binary_path} {status}                        |
| Hook            | PreToolUse·Bash {status}                      |
| Avg compression | {avg}% (from rtk gain)                        |
| Tokens saved    | ~{tokens} (this session)                      |
| Top commands    | {cmd1} {pct1}% · {cmd2} {pct2}%              |
```

Status icons: ✅ present/active · ❌ missing · ⚠️ below minimum version (0.31.0).

Degraded states:
- Binary not found + `XGH_SKIP_RTK` unset → `❌ RTK not installed — re-run install.sh (or set XGH_SKIP_RTK=1 to suppress)`
- Binary not found + `XGH_SKIP_RTK=1` → `⏭ RTK skipped (XGH_SKIP_RTK=1)`
- Version below `0.31.0` → `⚠️ RTK vX.Y.Z — upgrade to v0.31.0+ recommended`
- Binary missing but hook in settings → `❌ RTK binary missing at {path} — hook registered but inactive`
- `rtk gain` returns no data → `✅ RTK active — no Bash calls compressed yet this session`

### context-mode — context window protection

Call the `mcp__plugin_context-mode_context-mode__ctx_stats` MCP tool (no parameters). Format its output as:

```
#### context-mode — context window protection
| Metric          | Value                  |
|-----------------|------------------------|
| Version         | {version} ✅           |
| Plugin          | registered ✅          |
| Routing         | system-prompt active ✅|
| Sandbox calls   | {calls}                |
| Data sandboxed  | {kb} KB                |
| Context savings | {ratio}x               |
```

If `ctx_stats` unavailable: `❌ context-mode not active — run /xgh-setup`
If no calls yet: `✅ context-mode active — no sandbox calls yet this session`

## Check 4 — Scheduler

Call CronList. Find jobs where prompt is `/xgh-retrieve` or `/xgh-analyze`.

Also check if the pause file exists:
```bash
test -f ~/.xgh/scheduler-paused && echo "paused" || echo "active"
```

Report each job found:
- Job present → `✓ retrieve: active (*/5 * * * *)` / `✓ analyze: active (*/30 * * * *)`
- Job missing → `✗ retrieve: not scheduled` / `✗ analyze: not scheduled`
- Pause file absent → `✓ Scheduler active (always-on)`
- Pause file present → `⚠ Scheduler paused (~/.xgh/scheduler-paused exists)`

**Fix (if jobs missing or paused):** Run `/xgh-schedule resume` to re-register jobs now.

## Check 5 — Codebase index

For each project with `github:` entries, check `index.last_full` against `index.schedule`:
- Never indexed: ✗ (suggest `/xgh-index`)
- Overdue per schedule: ⚠
- Current: ✓

## Check 6 — Providers

List all directories in `~/.xgh/providers/`. For each:

1. Check `provider.yaml` exists and read `mode`
2. If `mode: bash`: check `fetch.sh` exists and is executable
   If `mode: mcp`: check `mcp.tools` section is non-empty in provider.yaml
3. Check `cursor` file — if it exists, report age (how long since last update)
4. Check last line of `~/.xgh/logs/provider-<name>.log` for errors

Report:
```
Providers
  ✓ github: 3 repos, bash mode, cursor 4 min ago
  ✓ slack: 2 channels, mcp mode (OAuth), cursor 4 min ago
  ✗ figma: fetch.sh missing — run /xgh-track to regenerate
  ⚠ jira: mcp mode, cursor 3 hours ago (stale — check MCP server)
```

Also check `~/.xgh/tokens.env`:
- File exists → report which vars are set (without showing values)
- File missing → `⚠ ~/.xgh/tokens.env not found — token-based providers will fail`

### Project detection

Run `bash ~/.xgh/scripts/detect-project.sh` and report:
- If a project was detected: `✓ Project scope: <name> (+N dependencies)`
- If no match: `ℹ No project detected — all-projects mode`
- If script missing: `⚠ detect-project.sh not installed — run /xgh-init`

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
  ✓ lossless-claude: connected (tool available)
  # Remote inference (when XGH_BACKEND=remote):
  ✓ Remote inference server: http://macmini.local:11434 — reachable, 2 models available
  # OR if unreachable:
  ✗ Remote inference server: http://192.168.1.100:11434 — unreachable (timeout)
    Fix: ensure the server is running and port 11434 is accessible from this machine
  ✗ lossless-claude: not in tool list — add to .claude/.mcp.json (command: lossless-claude, args: [mcp])

Pipeline
  ✓ Retriever: last run 3 min ago (healthy)
  ✗ Analyzer: last run 52 min ago (overdue — threshold: 45 min)

## Context Efficiency

### RTK — output compression
| Metric          | Value                              |
|-----------------|------------------------------------|
| Version         | v0.31.0 ✅ (min: v0.31.0)         |
| Binary          | ~/.local/bin/rtk ✅               |
| Hook            | PreToolUse·Bash registered ✅     |
| Avg compression | 73%                                |
| Tokens saved    | ~12,400 (this session)            |
| Top commands    | git log 91% · cargo build 84%     |

### context-mode — context window protection
| Metric          | Value                  |
|-----------------|------------------------|
| Version         | v1.0.22 ✅             |
| Plugin          | registered ✅          |
| Routing         | system-prompt active ✅|
| Sandbox calls   | 14                     |
| Data sandboxed  | 98.2 KB                |
| Context savings | 12.4x                  |

Scheduler
  ✓ Scheduler active (always-on)
  ✓ retrieve: active (*/5 * * * *)
  ✓ analyze: active (*/30 * * * *)
  # OR if paused/missing:
  ⚠ Scheduler paused (~/.xgh/scheduler-paused exists)
  ✗ retrieve: not scheduled
  ✗ analyze: not scheduled
    Fix: /xgh-schedule resume

Codebase Index
  ✓ acme-ios: indexed 2 days ago (schedule: weekly — OK)
  ✗ passcode-service: never indexed — run /xgh-index

Summary: 9 passed, 0 warnings, 2 failures
Fix: Check #channel-missing name. Run: claude -p "/xgh-analyze" to clear overdue analyzer.
```
