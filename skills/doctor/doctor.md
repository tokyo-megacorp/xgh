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

### RTK — output compression

Run these checks via Bash:

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

List all directories in `~/.xgh/user_providers/`. For each:

1. Check `provider.yaml` exists and read `mode`
2. If `mode: cli`: check `fetch.sh` exists and is executable
   If `mode: api`: check `fetch.sh` exists and is executable
   If `mode: mcp`: check `mcp.tools` section is non-empty in provider.yaml
3. Check `cursor` file — if it exists, report age (how long since last update)
4. Check last line of `~/.xgh/logs/provider-<name>.log` for errors

Report:
```
Providers
  ✓ github-cli: 3 repos, cli mode, cursor 4 min ago
  ✓ slack-mcp: 2 channels, mcp mode (OAuth), cursor 4 min ago
  ✗ figma-api: fetch.sh missing — run /xgh-track --regenerate figma-api
  ⚠ jira-mcp: mcp mode, cursor 3 hours ago (stale — check MCP server)
```

Also check for legacy providers:
```bash
ls ~/.xgh/providers/ 2>/dev/null
```
If `~/.xgh/providers/` exists with non-empty subdirectories:
```
⚠ Legacy providers found in ~/.xgh/providers/
  Run /xgh-track to migrate to ~/.xgh/user_providers/
```

Also check `~/.xgh/tokens.env`:
- File exists → report which vars are set (without showing values)
- File missing → `⚠ ~/.xgh/tokens.env not found — token-based providers will fail`

### Project detection

Run `bash ~/.xgh/scripts/detect-project.sh` and report:
- If a project was detected: `✓ Project scope: <name> (+N dependencies)`
- If no match: `ℹ No project detected — all-projects mode`
- If script missing: `⚠ detect-project.sh not installed — run /xgh-init`

## Check 7 — Trigger engine

Validate the trigger engine configuration and runtime state.

1. **Global config** — check `~/.xgh/triggers.yaml`:
   - ✅ exists and `enabled: true` and valid `action_level:`
   - ⚠️ exists but `enabled: false` — triggers are globally disabled
   - ❌ missing — run `/xgh-init` to create it

2. **Trigger directory** — check `~/.xgh/triggers/`:
   - Count `.yaml` files (exclude `.state.json`)
   - Count enabled triggers (`enabled: true`) vs disabled
   - ✅ `N triggers (M enabled)`
   - ⚠️ `0 triggers defined` — no triggers yet (see `triggers/examples/` for inspiration)

3. **Trigger state** — check `~/.xgh/triggers/.state.json`:
   - List any triggers currently silenced (silenced_until in the future)
   - Report triggers that fired in the last 24h
   - ⚠️ if any trigger has `fire_count > 10` with backoff — may be stuck in backoff loop

4. **Hook registration** — check if PostToolUse hook is active:
   - Run `claude config list` and check for post-tool-use hook
   - ✅ PostToolUse hook registered (local command triggers will work)
   - ⚠️ PostToolUse hook not found — `source: local` triggers won't fire automatically.
     Run `/xgh-setup` to configure.

5. **Example output:**
   ```
   Check 7: Trigger engine
   ✅ Global config: enabled=true | action_level=create | fast_path=true
   ✅ 4 triggers (3 enabled, 1 disabled)
   ⚠️ pr-stale-reminder: silenced until 2026-03-22T09:00:00Z
   ✅ Fired last 24h: p0-alert (2 times)
   ⚠️ PostToolUse hook not registered — source:local triggers inactive
   ```

## Check 8 — Agent version parity

For each secondary agent in `config/agents.yaml` with a `tested_version` field (non-null):

1. Check if the agent is installed: `command -v <agent> >/dev/null 2>&1`
2. If installed, get its version: `<agent> --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1`
3. Compare against `tested_version` in the registry

Report:
```
Agent versions
  ✓ codex: v0.116.0 (tested: 0.116.0 — exact match)
  ⚠ codex: v0.120.0 (tested: 0.116.0 — newer, behaviors may differ)
  ✗ codex: v0.100.0 (tested: 0.116.0 — older, some flags may be missing)
  ⚠ gemini: tested_version not set — run /xgh-doctor after first use to record it
  - opencode: not installed
```

Rules:
- Exact match → ✓
- Installed version > tested → ⚠ (minor: newer may have renamed flags or changed behavior)
- Installed version < tested → ✗ (major: flags we rely on may not exist yet)
- `tested_version: null` and agent installed → ⚠ (no baseline recorded)
- Agent not installed → skip (only flag if installed)

**Fix for mismatch:** Re-test the affected skill (`/xgh-codex`, `/xgh-gemini`) and update `tested_version` in `config/agents.yaml` if behaviors are confirmed working.

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

Agent Versions
  ✓ codex: v0.116.0 (tested: 0.116.0)
  ⚠ gemini: tested_version not set — update config/agents.yaml after validating
  - opencode: not installed

Summary: 9 passed, 0 warnings, 2 failures
Fix: Check #channel-missing name. Run: claude -p "/xgh-analyze" to clear overdue analyzer.
```
