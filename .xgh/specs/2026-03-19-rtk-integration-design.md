# RTK Full Integration — Design Spec
**Date:** 2026-03-19
**Status:** Approved for implementation

---

## Overview

Integrate RTK (https://github.com/rtk-ai/rtk) as a first-class xgh dependency alongside context-mode. RTK is a Rust CLI that compresses Bash command output (60–90% token reduction) via a `PreToolUse` hook. It acts as a safety net for Path B (agent bypasses context-mode routing and calls Bash directly), while context-mode remains the primary context protection mechanism for Path A (agent uses `ctx_*` tools).

---

## Architecture

Two complementary layers with zero overlap:

```
Raw CLI output (huge)
      │
      ├── Path A: agent uses ctx_* tools
      │         → context-mode sandbox
      │         → distilled results (small, structured)
      │         → RTK never fires
      │
      └── Path B: agent calls Bash directly
                → RTK PreToolUse hook intercepts
                → rtk <cmd> runs internally (subprocess)
                → compressed output returned (60–90% smaller)
                → original Bash call suppressed
```

**Why RTK does not apply to context-mode tool outputs:** context-mode MCP tools (`ctx_batch_execute`, `ctx_search`, `ctx_execute`) already return distilled, structured results. RTK's compression algorithms target raw CLI output patterns; applying them to pre-distilled markdown/JSON would corrupt formatting the agent depends on.

**Why there is no hook-level clash:** context-mode operates via system prompt injection (plugin manifest injects routing instructions at session start). It does not register a `PreToolUse` hook on Bash. RTK's `PreToolUse` Bash hook is the only interceptor at that layer.

---

## Install (`install.sh`)

### New lane

Added after the context-mode install step, before lossless-claude:

```bash
lane "Installing RTK 🗜️"
```

### Skip flag

```bash
XGH_SKIP_RTK=1  # suppresses RTK install entirely
```

Mirrors the existing `XGH_SKIP_LCM=1` pattern. If set, no binary is downloaded, no hook is registered, doctor shows a neutral note (not an error).

### Binary installation steps

1. **Check if already installed** — if `rtk --version` succeeds and version ≥ `RTK_MIN_VERSION`, skip download (idempotent).
2. **Detect architecture** — use `uname -m` plus `sysctl hw.optional.arm64` cross-check on macOS to correctly identify Apple Silicon even under Rosetta.
3. **Resolve latest release** — call GitHub API (`https://api.github.com/repos/rtk-ai/rtk/releases/latest`). If API returns non-200 (rate limit, network failure), fall back to hardcoded `RTK_MIN_VERSION`.
4. **Select asset URL** — map arch+OS to the correct release asset:
   - `aarch64-apple-darwin` → `rtk-aarch64-apple-darwin.tar.gz`
   - `x86_64-apple-darwin` → `rtk-x86_64-apple-darwin.tar.gz`
   - `aarch64-linux` → `rtk-aarch64-unknown-linux-gnu.tar.gz`
   - `x86_64-linux` → `rtk-x86_64-unknown-linux-musl.tar.gz`
5. **Download binary + checksum file** — curl the binary tarball and the checksum asset. The checksum asset name must be discovered from the GitHub API release response (look for an asset named `checksums.txt` in the `assets` array; if absent, look for a `.sha256` sidecar matching the binary asset name). Do not hardcode the checksum filename.
6. **Verify SHA256** — abort and warn if checksum mismatch; do not install corrupt binary.
7. **Install binary** — extract to `~/.local/bin/rtk`; `mkdir -p ~/.local/bin`; `chmod +x`.
8. **Confirm** — run `rtk --version`; warn and continue if it fails (never block xgh install).

### Constants

```bash
RTK_MIN_VERSION="0.31.0"
RTK_REPO="rtk-ai/rtk"
RTK_INSTALL_DIR="${HOME}/.local/bin"
```

---

## Hook Registration

RTK registers one hook entry in the `PreToolUse` section of `$SETTINGS_FILE` (the variable resolved during xgh install — either `~/.claude/settings.json` for global scope or `.claude/settings.local.json` for project scope). RTK uses the same `$SETTINGS_FILE` and `$XGH_HOOKS_SCOPE` as all other xgh hooks.

Hook entry:
```json
{
  "matcher": "Bash",
  "hooks": [{ "type": "command", "command": "<absolute-path-to-rtk> hook --quiet" }]
}
```

The absolute path is captured at install time: `RTK_BIN="$(command -v rtk || echo "${RTK_INSTALL_DIR}/rtk")"`.

**Merge method:** RTK's hook entry is injected via a dedicated step in `install.sh` using the same Python deep-merge function already used for xgh's other hooks. It is **not** added to `config/hooks-settings.json` (which uses `__HOOKS_DIR__` placeholder resolution for script-based hooks). RTK uses an absolute binary path, so it bypasses the template and merges directly. The implementer should add a `merge_rtk_hook()` function in `install.sh` parallel to the existing hooks merge step, called after binary install is confirmed.

Rules:
- **Full binary path** — no PATH dependency; Claude Code hook execution environment may not inherit user's shell PATH.
- **`--quiet` flag** — suppresses RTK's advice output to keep context clean; context-mode's routing guidance is the primary signal.
- **Placement** — appended after any existing `PreToolUse.Bash` entries in the merge; context-mode's system prompt fires before any tool call so ordering within `PreToolUse` is not a concern.
- **Conditional registration** — only added if binary is confirmed present after install. If install failed or was skipped, `$SETTINGS_FILE` is not modified.
- **Idempotent** — xgh's existing Python deep-merge logic deduplicates hook entries by `command` value; re-running install does not add duplicate hooks.

---

## `/xgh-doctor` — Unified Context Efficiency Dashboard

New `### Context Efficiency` section added to the doctor skill output.

### RTK subsection

Data source: `rtk gain --json` piped via `ctx_execute`.

```
#### RTK — output compression
| Metric              | Value                                    |
|---------------------|------------------------------------------|
| Version             | v0.31.0 ✅  (min: v0.31.0)               |
| Binary              | ~/.local/bin/rtk ✅                      |
| Hook                | PreToolUse·Bash registered ✅            |
| Avg compression     | 73%                                      |
| Tokens saved        | ~12,400 (this session)                   |
| Top commands        | git log 91% · cargo build 84% · pytest 79% |
```

### context-mode subsection

Data source: the agent calls the `ctx_stats` MCP tool at runtime (`mcp__plugin_context-mode_context-mode__ctx_stats`) and formats the returned JSON into the table below. The `doctor.md` skill instructions tell the agent to call this tool and render its output — there is no code-level execution in the skill file itself.

```
#### context-mode — context window protection
| Metric          | Value                  |
|-----------------|------------------------|
| Version         | v1.0.22 ✅             |
| Plugin          | registered ✅           |
| Routing         | system-prompt active ✅ |
| Sandbox calls   | 14                     |
| Data sandboxed  | 98.2 KB                |
| Context savings | 12.4x                  |
```

### Degraded states

| Condition | Output |
|-----------|--------|
| RTK not installed, `XGH_SKIP_RTK` not set | `❌ RTK not installed — re-run install.sh (or set XGH_SKIP_RTK=1 to suppress)` |
| RTK not installed, `XGH_SKIP_RTK=1` | `⏭ RTK skipped (XGH_SKIP_RTK=1)` |
| RTK below min version | `⚠️ RTK v0.28.0 — upgrade to v0.31.0+ recommended` |
| Binary missing, hook registered | `❌ RTK binary missing at <path> — hook registered but inactive` |
| `rtk gain` returns no data | `✅ RTK active — no Bash calls compressed yet this session` |
| context-mode inactive | `❌ context-mode not active — run /xgh-setup` |
| `ctx_stats` unavailable | `⚠️ context-mode stats unavailable` |

---

## Failure Modes & Mitigations

| Failure | Impact | Mitigation |
|---------|--------|------------|
| Binary download fails | RTK not installed | Warn and continue; never block xgh install |
| GitHub API rate limited | Wrong version selected | Fall back to `RTK_MIN_VERSION` |
| SHA256 mismatch | Abort install | Log error; do not install; warn user |
| Wrong arch detected (Rosetta) | Binary won't run | Cross-check `uname -m` with `sysctl hw.optional.arm64` |
| Binary not in hook's PATH | Hook silently fails | Register with full absolute path |
| Binary later removed | Hook fails silently | Doctor detects and flags `❌ binary missing` |
| RTK version drift (API change) | `rtk hook` or `rtk gain` broken | Doctor checks version against `RTK_MIN_VERSION`; warns if below |
| Hook output noise | Agent sees conflicting advice | `--quiet` flag suppresses RTK hook output |

---

## Files to Create/Modify

| File | Change |
|------|--------|
| `install.sh` | Add RTK lane: arch detection, curl+verify, binary install, hook registration |
| `plugin/skills/doctor/doctor.md` | Add `### Context Efficiency` section with RTK + context-mode dashboards |
| `tests/test-install.sh` | Add assertions: binary exists, hook registered, SHA256 verified, skip flag works |

---

## What Does NOT Change

- context-mode install (still `claude plugin install`)
- lossless-claude install (still `npm install -g`)
- xgh hook registration logic (RTK reuses the existing scope + merge pattern)
- context-mode MCP tool API or routing behaviour
- lossless-claude cross-session memory
- xgh context tree

---

## Verification Checklist

**Dry-run / structural (testable in `test-install.sh` with `XGH_DRY_RUN=1`):**
1. `XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh` — RTK lane message visible, no errors
2. `XGH_SKIP_RTK=1 XGH_DRY_RUN=1 bash install.sh` — RTK lane skipped, no hook added
3. RTK lane code exists in `install.sh` (grep assertion)
4. `XGH_SKIP_RTK=1`: doctor skill text contains `⏭ RTK skipped` (static assertion)

**Live install (requires network; run outside dry-run in CI or manual test):**
5. `~/.local/bin/rtk --version` returns ≥ `RTK_MIN_VERSION`
6. `$SETTINGS_FILE` contains RTK `PreToolUse` Bash hook with full absolute path
7. Checksum asset name is discovered dynamically from GitHub API (not hardcoded)
8. Corrupt binary test: tampered tarball → install aborts with checksum error, no binary written

**Runtime (manual, in a live Claude session):**
9. `/xgh-doctor` shows `### Context Efficiency` with both RTK and context-mode subsections
10. After a `git log` Bash call: RTK gain > 0 in doctor dashboard
11. After a `ctx_batch_execute` call: RTK gain unchanged (RTK did not fire)
