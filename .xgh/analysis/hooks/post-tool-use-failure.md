---
hook: PostToolUseFailure
analyzed_by: sonnet
date: 2026-03-25
context: xgh project.yaml config system design
---

# PostToolUseFailure Hook Analysis

## 1. Hook Spec

**When it fires**: After any tool execution returns a non-zero exit code or an error payload. It does not fire when a tool succeeds, even if the result is semantically wrong (e.g., `gh pr create` succeeds but assigns the wrong reviewer).

**Input payload** (JSON on stdin):
```json
{
  "tool_name": "Bash",
  "tool_input": { "command": "gh pr merge --squash ..." },
  "error": "exit status 1",
  "output": "GraphQL: Pull request is not mergeable (squashMerge disabled)"
}
```
Fields: `tool_name` (string), `tool_input` (object, matches tool schema), `error` (string), `output` (stderr/stdout captured up to failure).

**Output**: The hook can write a JSON response to stdout with:
- `"action": "block"` — prevents the agent from continuing and surfaces the error message to the user.
- `"action": "warn"` — appends a warning to the next model turn without blocking.
- No output / empty — hook is informational only; agent proceeds normally.

---

## 2. Capabilities

**Error logging**: The hook receives both the tool name and its full input, so failures can be persisted to a structured log (e.g., `.xgh/logs/tool-failures.jsonl`) with timestamp, tool, command, and error text. This creates an auditable trail without adding noise to the model context.

**Recovery suggestions**: By pattern-matching `error` and `output` text, the hook can inject a targeted suggestion into the next turn — e.g., "This looks like a merge-method mismatch; check `pr.branches.main.merge_method` in `config/project.yaml`."

**Failure pattern detection**: Repeated failures on the same tool/command class can be counted in a lightweight counter file. When a threshold is crossed (e.g., 3 identical `gh` failures in a session), the hook can escalate from `warn` to `block` and prompt a config review.

---

## 3. Opportunities for xgh

### 3.1 Config-mismatch detection

The `load_pr_pref` read order is: CLI flag → branch override → project default → probe. Failures that occur after config resolution (e.g., "Merge method not allowed") indicate a drift between `project.yaml` and the actual GitHub repo settings — not a user error. The hook can detect this class by matching known GitHub API error strings and emit:

```
[xgh] project.yaml sets merge_method: squash for `main`, but the repo
      has squash merging disabled. Run `/xgh-refresh` or update the repo
      branch protection settings.
```

This turns an opaque GraphQL error into an actionable config fix.

### 3.2 Stale reviewer detection

The `reviewer` field (`copilot-pull-request-reviewer[bot]`) is hardcoded in `project.yaml`. If `gh pr create --reviewer copilot-pull-request-reviewer[bot]` fails with a "reviewer not found" or "collaborator not enabled" error, it signals the Copilot reviewer integration was disabled or the bot login changed. The hook can match this pattern and suggest:

```
[xgh] Reviewer `copilot-pull-request-reviewer[bot]` was rejected.
      Copilot code review may be disabled for this repo.
      Update `pr.reviewer` in config/project.yaml or re-enable the integration.
```

### 3.3 Wrong-repo guard

When `probe_pr_field("repo")` falls back to `gh repo view`, it reads the remote origin at call time. If someone runs an xgh skill from a cloned fork, `tool_input.command` will contain a different `owner/repo` than what's in `project.yaml`. The hook can compare the repo slug in the failing command against the cached `pr.repo` value and warn:

```
[xgh] Command targeted `fork-owner/xgh` but project.yaml declares
      `tokyo-megacorp/xgh`. You may be running from a fork.
      Override with XGH_REPO or update config/project.yaml.
```

---

## 4. Pitfalls

**Fires on tool failure only, not skill logic errors**: If a skill reads the wrong merge method from `project.yaml` but the downstream `gh` call succeeds with that wrong value, `PostToolUseFailure` never fires. Silent misconfigurations are invisible to this hook.

**Limited recovery ability**: The hook cannot re-run the tool or mutate `tool_input` before retry. Its power is informational. Actual remediation must be triggered by the model in a subsequent turn, meaning recovery adds at least one round-trip.

**Risk of noisy logging**: Every failed Bash command fires this hook — including benign probe failures inside `probe_pr_field` itself (e.g., `git remote get-url origin` in a non-git directory). Without careful filtering, the log fills with expected-failure noise from the config-reader's own fallback chain. Filter criteria: only log when `tool_name` is `Bash` and `error` contains a non-zero exit from a `gh`, `git push`, or `glab` call.

**No access to resolved config state**: The hook sees `tool_input` (the raw command string) but not the xgh config state at the time of the call. Inferring which config value caused a failure requires string parsing of the command, which is fragile.

---

## 5. Concrete Implementations

### Implementation A — `hooks/post-tool-use-failure.sh` (merge-method guard)

```bash
#!/usr/bin/env bash
# PostToolUseFailure: detect merge-method mismatch errors
set -euo pipefail

input=$(cat)
error=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('output',''))")

if echo "$error" | grep -qi "squash.*not allowed\|merge method.*disabled\|not mergeable"; then
  branch=$(echo "$input" | python3 -c "
import sys,json,re
d=json.load(sys.stdin)
cmd=d.get('tool_input',{}).get('command','')
m=re.search(r'--base[= ](\S+)', cmd)
print(m.group(1) if m else 'this branch')
")
  cat <<JSON
{
  "action": "warn",
  "message": "[xgh] Merge-method mismatch on ${branch}. Check pr.branches.${branch}.merge_method in config/project.yaml against the repo's branch protection settings."
}
JSON
fi
```

### Implementation B — `hooks/post-tool-use-failure.sh` (structured failure log)

```bash
#!/usr/bin/env bash
# PostToolUseFailure: append structured entry to .xgh/logs/tool-failures.jsonl
set -euo pipefail
LOG_FILE="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")/.xgh/logs/tool-failures.jsonl"
mkdir -p "$(dirname "$LOG_FILE")"
input=$(cat)
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "$input" | python3 -c "
import sys,json
d=json.load(sys.stdin)
d['ts']='${timestamp}'
print(json.dumps(d))
" >> "$LOG_FILE"
```

This produces a queryable JSONL log. A future `/xgh-health` skill can scan it for repeated patterns and surface config-drift signals without polluting model context during normal operation.

### Implementation C — stale-reviewer warn (inline pattern)

Extend the same hook script with a second check block:

```bash
if echo "$error" | grep -qi "reviewer.*not found\|could not resolve to a User\|collaborator"; then
  reviewer=$(git config --get xgh.reviewer 2>/dev/null \
    || python3 -c "
import yaml
with open('config/project.yaml') as f: d=yaml.safe_load(f)
print(d.get('preferences',{}).get('pr',{}).get('reviewer',''))
" 2>/dev/null || echo "configured reviewer")
  cat <<JSON
{
  "action": "warn",
  "message": "[xgh] Reviewer '${reviewer}' was rejected. The Copilot review integration may be disabled or the bot login changed. Update pr.reviewer in config/project.yaml."
}
JSON
fi
```

---

## Summary

`PostToolUseFailure` is a **diagnostic amplifier**, not a recovery mechanism. Its highest-value use in xgh is bridging the gap between opaque provider API errors and the config values in `project.yaml` that caused them. The three failure classes most worth targeting — merge-method mismatch, stale reviewer, and wrong-repo fork — all map directly to fields in `preferences.pr`. Keeping the hook lightweight (pattern match + structured log) avoids the noise pitfall and leaves remediation to the model.
