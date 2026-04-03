---
hook: PreToolUse
analyzed_by: sonnet
date: 2026-03-25
context: xgh project.yaml config system design
---

# PreToolUse Hook — Analysis for xgh

## 1. Hook Spec

**When it fires**: Before any Claude Code tool call executes. The hook runs synchronously — the tool call is blocked until the hook process exits.

**Matcher**: Configured in `.claude/settings.json` under `hooks.PreToolUse`. You can match specific tools (`Bash`, `Edit`, `Write`, `mcp__*`) or use `"*"` to match all.

**Input** (delivered via stdin as JSON):

```json
{
  "session_id": "abc123",
  "tool_name": "Bash",
  "tool_input": {
    "command": "gh pr merge 42 --squash"
  }
}
```

**Output** (hook writes JSON to stdout, exits 0 for allow/modify, exits non-zero to block):

```json
{
  "decision": "allow" | "block",
  "reason": "Human-readable explanation shown to the user",
  "hookSpecificOutput": {
    "permissionDecision": "allow" | "block",
    "updatedInput": { ... },
    "additionalContext": "String injected into the model's context before the tool runs"
  }
}
```

Exit code semantics:
- `exit 0` with no stdout → allow, unmodified
- `exit 0` with JSON stdout → allow or block per `decision` field
- `exit 1+` → block unconditionally (stderr shown as reason)

---

## 2. Capabilities

| Output field | Effect |
|---|---|
| `decision: "block"` | Tool call is cancelled. Claude sees `reason` and can adapt. |
| `decision: "allow"` | Tool proceeds. Implicit if hook exits 0 with no output. |
| `hookSpecificOutput.permissionDecision` | Fine-grained allow/block alongside other output fields. |
| `hookSpecificOutput.updatedInput` | **Replaces** `tool_input` before the tool executes. Claude never sees the substitution. |
| `hookSpecificOutput.additionalContext` | String prepended to the model's context window for this tool call only. The model can read it; it does not affect what the tool actually receives. |

Key constraint: `updatedInput` is a full replacement of `tool_input`, not a merge. The hook must preserve all fields it does not intend to modify.

---

## 3. Opportunities for xgh

xgh's mission is "declarative AI ops — declare agent behavior in YAML, converge every AI platform to match." The PreToolUse hook is the enforcement layer that makes `config/project.yaml` preferences **binding** rather than advisory.

### 3a. Preference injection — make project.yaml the single source of truth

Skills already call `load_pr_pref` at runtime, but they can be bypassed. A PreToolUse hook on `Bash` tool calls matching `gh pr merge` or `gh pr create` can:

1. Read `preferences.pr.merge_method` from `config/project.yaml` via `xgh_config_get`.
2. Inject the correct `--squash`/`--merge`/`--rebase` flag into `updatedInput.command`, overriding whatever the skill or user supplied.
3. Set `additionalContext` to explain why: *"Merge method forced to squash per project.yaml preferences.pr.merge_method."*

This closes the gap between documented preference and actual behavior — no skill can silently use the wrong merge method.

### 3b. Config validation guardrails

Before any tool call that writes to `.xgh/` or `config/`, validate that the result will be consistent:

- Block `Write` or `Edit` calls that would set `preferences.pr.merge_method: merge` on a repo where `branches.main.merge_method` is already overriding to `squash`.
- Surface the conflict via `reason` with a pointer to the spec.

This is the terraform-plan analogy: catch drift at the point of change, not after.

### 3c. Context enrichment for skill calls

When a skill invokes a tool like `gh pr create`, inject `additionalContext` that includes the current resolved preference cascade:

```
[xgh config snapshot]
provider: github
repo: tokyo-megacorp/xgh
merge_method: squash (branch override: main → merge)
reviewer: copilot-pull-request-reviewer[bot]
auto_merge: true
```

The model can use this to make correct downstream decisions without re-reading config files mid-skill. This is especially valuable in long multi-step skills where config state could drift between steps.

---

## 4. Pitfalls

**Performance**: PreToolUse fires on **every matched tool call**. A hook that shells out to Python (as `xgh_config_get` does via `safe_load`) adds ~50–200ms per tool call. For sessions with hundreds of `Bash` calls, this compounds. Mitigations: cache the parsed YAML in a temp file keyed by mtime; use a pure-bash YAML parser for scalar reads; restrict matchers to specific tools.

**Silent modification**: `updatedInput` replaces tool input invisibly. If the hook has a bug (e.g., malformed command substitution), the tool silently receives garbage. The model sees success, the user sees a wrong outcome, and there is no diff to inspect. Always log modifications to stderr so they appear in Claude's hook output display.

**Debugging difficulty**: Hook failures show terse messages. A hook that exits non-zero with no stderr provides no signal. Establish a convention: always write `[xgh-hook] <reason>` to stderr on any non-trivial decision.

**Scope creep**: The hook runs before the tool, not after. It cannot observe tool output. Logic that depends on what a command produced (e.g., "did the PR merge succeed?") belongs in PostToolUse, not here.

**Order sensitivity**: Multiple hooks on the same matcher run in definition order. If xgh installs a hook and the user also has a global hook, the interaction is additive and potentially conflicting. xgh hooks should be idempotent and narrow in scope.

---

## 5. Concrete Implementations

### Implementation A — `xgh-pre-tool-merge-enforcer.sh`

**Matcher**: `Bash` tool calls containing `gh pr merge`

**Logic**:
1. Parse `tool_input.command` from stdin JSON.
2. Call `xgh_config_get preferences.pr.merge_method` (with mtime-based YAML cache).
3. Strip any existing `--squash/--merge/--rebase` flag from the command.
4. Inject the project-configured flag.
5. Return `updatedInput` with the corrected command + `additionalContext` explaining the substitution.

**Value**: The `/release` skill's recent `--squash` fix (commit `7731a73`) would have been unnecessary — the hook enforces it unconditionally.

---

### Implementation B — `xgh-pre-tool-context-injector.sh`

**Matcher**: All `mcp__*` tool calls (skill invocations) and `Bash` calls starting with `gh`

**Logic**:
1. At session start (or on first match), resolve the full preference cascade via `load_pr_pref` for all known keys.
2. Serialize the snapshot to a temp file.
3. On each match, read the snapshot and return it as `additionalContext`.
4. Re-resolve only if `config/project.yaml` mtime has changed.

**Value**: Every skill and MCP tool call gets a consistent config snapshot in context. No skill needs to re-read config mid-execution. Eliminates the class of bugs where a skill hardcodes a value because config reading felt expensive.

---

### Implementation C — `xgh-pre-tool-write-guard.sh`

**Matcher**: `Write` and `Edit` tool calls targeting `config/project.yaml` or any `.xgh/` path

**Logic**:
1. Capture `tool_input.file_path` and `tool_input.new_string` / `tool_input.content`.
2. Run the proposed content through a validation script that checks for known conflicts (e.g., `merge_method: merge` on a squash-only repo, missing required keys, invalid provider values).
3. On conflict: `decision: block` with a `reason` that cites the specific rule and the spec path `.xgh/specs/`.
4. On pass: `decision: allow` with `additionalContext` summarizing what changed and what downstream effects to expect.

**Value**: This is the terraform-validate equivalent — declarative config changes are validated before they land, not discovered at skill runtime.
