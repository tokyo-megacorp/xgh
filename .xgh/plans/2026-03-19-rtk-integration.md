# RTK Full Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate RTK as a first-class xgh dependency — installed via curl, hooked into Claude Code's Bash PreToolUse, and surfaced as a unified Context Efficiency dashboard in `/xgh-doctor`.

**Architecture:** RTK is a Rust binary that compresses Bash command output (60–90%) by intercepting via a `PreToolUse` hook. It operates on Path B only (agent calls Bash directly); when the agent correctly uses `ctx_*` tools (Path A), RTK never fires. Both are surfaced together in `/xgh-doctor` as a unified dashboard. Hook registration reuses the existing `$SETTINGS_FILE`/deep-merge infrastructure from section 5 of `install.sh`.

**Tech Stack:** Bash (`install.sh`), Python 3 (deep-merge, SHA256 verify), Markdown (doctor skill, agent instructions), xgh test harness (`assert_*` helpers).

**Spec:** `.xgh/specs/2026-03-19-rtk-integration-design.md`

---

## File Map

| File | Change |
|------|--------|
| `install.sh` | Add RTK lane (arch detect, curl, SHA256 verify, binary install) + `merge_rtk_hook()` function |
| `plugin/skills/doctor/doctor.md` | Add `### Context Efficiency` section with RTK + context-mode subsections |
| `tests/test-install.sh` | Add RTK dry-run structural assertions + skip flag assertions |

---

## Task 1: RTK Install Lane (binary download)

**Files:**
- Modify: `install.sh` — add RTK lane after context-mode install block, before lossless-claude lane
- Modify: `tests/test-install.sh` — add structural dry-run assertions

### Step 1.1 — Write the failing tests first

Add to `tests/test-install.sh`, before the final `echo "Install test: ..."` line:

```bash
# ── RTK ──────────────────────────────────────────────────────────────────────
echo ""
echo "── RTK ──"

# Lane code exists in install.sh
assert_contains "${XGH_LOCAL_PACK}/install.sh" 'lane "Installing RTK'

# Skip flag suppresses install
assert_contains "${XGH_LOCAL_PACK}/install.sh" 'XGH_SKIP_RTK'

# Arch detection uses both uname and sysctl cross-check
assert_contains "${XGH_LOCAL_PACK}/install.sh" 'hw.optional.arm64'

# GitHub API call with fallback
assert_contains "${XGH_LOCAL_PACK}/install.sh" 'RTK_MIN_VERSION'
assert_contains "${XGH_LOCAL_PACK}/install.sh" 'releases/latest'

# SHA256 verification
assert_contains "${XGH_LOCAL_PACK}/install.sh" 'sha256'

# Skip flag: no hook added when XGH_SKIP_RTK=1
XGH_SKIP_RTK=1 XGH_DRY_RUN=1 XGH_LOCAL_PACK="${XGH_LOCAL_PACK}" bash "${XGH_LOCAL_PACK}/install.sh" > /tmp/rtk-skip-out.txt 2>&1 || true
assert_contains /tmp/rtk-skip-out.txt 'XGH_SKIP_RTK'
```

- [ ] **Step 1.1:** Add the test block above to `tests/test-install.sh`

- [ ] **Step 1.2: Run tests — verify they fail**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash tests/test-install.sh 2>&1 | tail -20
```

Expected: several `FAIL: install.sh missing 'lane "Installing RTK'` lines and similar.

### Step 1.3 — Add constants and arch detection helper to `install.sh`

Find the block near the top of `install.sh` where other constants are set (search for `XGH_REPO=`). Add immediately after:

```bash
# ── RTK constants ─────────────────────────────────────────
RTK_MIN_VERSION="0.31.0"
RTK_REPO="rtk-ai/rtk"
RTK_INSTALL_DIR="${HOME}/.local/bin"

# Detect CPU arch, cross-checking for Rosetta on macOS
_rtk_arch() {
  local arch
  arch="$(uname -m)"
  # On macOS, verify we are not running x86_64 Rosetta on Apple Silicon
  if [ "$arch" = "x86_64" ] && [ "$(uname -s)" = "Darwin" ]; then
    if sysctl hw.optional.arm64 2>/dev/null | grep -q ': 1'; then
      arch="aarch64"
    fi
  elif [ "$arch" = "arm64" ]; then
    arch="aarch64"
  fi
  echo "$arch"
}
```

- [ ] **Step 1.3:** Add constants + `_rtk_arch()` to `install.sh`

### Step 1.4 — Add the RTK install lane

Find section 6 (Settings merge) — search for `lane "Tuning permissions"` or `# ── 6. Settings`. Insert the RTK lane immediately **after** that section ends (after the `fi` that closes the settings merge block) and **before** the Plugin Registration lane. Do NOT place it before the lossless-claude lane — `$SETTINGS_FILE` is set in section 5 (Hooks) and `merge_rtk_hook` in Task 2 depends on it being set.

```bash
# ── 3a. RTK — output compression ─────────────────────────
lane "Installing RTK 🗜️"

if [ "$XGH_DRY_RUN" -eq 0 ] && [ "${XGH_SKIP_RTK:-0}" -eq 0 ]; then
  _RTK_BIN=""

  # Idempotent: check if already installed and meets min version
  if command -v rtk &>/dev/null; then
    _installed_ver="$(rtk --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo '0.0.0')"
    if python3 -c "
v=tuple(int(x) for x in '${_installed_ver}'.split('.'))
m=tuple(int(x) for x in '${RTK_MIN_VERSION}'.split('.'))
exit(0 if v >= m else 1)
" 2>/dev/null; then
      info "RTK already installed: $(command -v rtk) (${_installed_ver})"
      _RTK_BIN="$(command -v rtk)"
    fi
  fi

  if [ -z "$_RTK_BIN" ]; then
    _arch="$(_rtk_arch)"
    _os="$(uname -s | tr '[:upper:]' '[:lower:]')"

    # Map arch+os to release asset name
    case "${_arch}-${_os}" in
      aarch64-darwin) _asset="rtk-aarch64-apple-darwin.tar.gz" ;;
      x86_64-darwin)  _asset="rtk-x86_64-apple-darwin.tar.gz" ;;
      aarch64-linux)  _asset="rtk-aarch64-unknown-linux-gnu.tar.gz" ;;
      x86_64-linux)   _asset="rtk-x86_64-unknown-linux-musl.tar.gz" ;;
      *)
        warn "RTK: unsupported platform ${_arch}-${_os} — skipping"
        _asset=""
        ;;
    esac

    if [ -n "$_asset" ]; then
      # Resolve latest release tag; fall back to RTK_MIN_VERSION
      _tag="$(curl -sf "https://api.github.com/repos/${RTK_REPO}/releases/latest" \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name','v${RTK_MIN_VERSION}'))" \
        2>/dev/null || echo "v${RTK_MIN_VERSION}")"
      _tag="${_tag:-v${RTK_MIN_VERSION}}"

      _base_url="https://github.com/${RTK_REPO}/releases/download/${_tag}"
      _tmpdir="$(mktemp -d)"

      info "Downloading RTK ${_tag} (${_asset})..."
      if curl -sfL "${_base_url}/${_asset}" -o "${_tmpdir}/${_asset}"; then

        # Discover checksum asset name from API; fall back to checksums.txt
        _checksum_asset="$(curl -sf "https://api.github.com/repos/${RTK_REPO}/releases/latest" \
          | python3 -c "
import json,sys
assets=[a['name'] for a in json.load(sys.stdin).get('assets',[])
        if 'checksum' in a['name'].lower() or a['name'].endswith('.sha256')]
print(assets[0] if assets else 'checksums.txt')
" 2>/dev/null || echo "checksums.txt")"

        curl -sfL "${_base_url}/${_checksum_asset}" -o "${_tmpdir}/checksums.txt" 2>/dev/null || true

        # Verify SHA256 if checksum file downloaded
        _verified=0
        if [ -s "${_tmpdir}/checksums.txt" ]; then
          _expected="$(grep "${_asset}" "${_tmpdir}/checksums.txt" | awk '{print $1}')"
          if [ -n "$_expected" ]; then
            _actual="$(sha256sum "${_tmpdir}/${_asset}" 2>/dev/null | awk '{print $1}' || shasum -a 256 "${_tmpdir}/${_asset}" 2>/dev/null | awk '{print $1}')"
            if [ "$_actual" = "$_expected" ]; then
              _verified=1
            else
              warn "RTK: SHA256 mismatch — aborting install (expected ${_expected}, got ${_actual})"
              rm -rf "$_tmpdir"
              _asset=""
            fi
          else
            # Checksum not found for this asset — proceed without verification, warn
            warn "RTK: no checksum entry found for ${_asset} — installing without verification"
            _verified=1
          fi
        else
          warn "RTK: could not fetch checksums — installing without verification"
          _verified=1
        fi

        if [ "$_verified" -eq 1 ] && [ -n "$_asset" ]; then
          mkdir -p "${RTK_INSTALL_DIR}"
          tar -xzf "${_tmpdir}/${_asset}" -C "${_tmpdir}" 2>/dev/null || true
          _extracted_bin="$(find "${_tmpdir}" -type f -name 'rtk' | head -1)"
          if [ -n "$_extracted_bin" ]; then
            mv "$_extracted_bin" "${RTK_INSTALL_DIR}/rtk"
            chmod +x "${RTK_INSTALL_DIR}/rtk"
            _RTK_BIN="${RTK_INSTALL_DIR}/rtk"
            info "RTK installed: ${_RTK_BIN}"
          else
            warn "RTK: binary not found in archive — skipping"
          fi
        fi
      else
        warn "RTK: download failed — skipping (set XGH_SKIP_RTK=1 to suppress)"
      fi
      rm -rf "$_tmpdir"
    fi
  fi

  # Confirm binary works
  if [ -n "$_RTK_BIN" ]; then
    "$_RTK_BIN" --version &>/dev/null || warn "RTK binary installed but --version failed"
  fi

else
  [ "${XGH_SKIP_RTK:-0}" -eq 1 ] && info "Skipping RTK (XGH_SKIP_RTK=1)"
fi
```

- [ ] **Step 1.4:** Add the RTK lane to `install.sh`

- [ ] **Step 1.5: Run tests — verify they pass**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash tests/test-install.sh 2>&1 | tail -20
```

Expected: all RTK structural assertions pass. Full run shows `0 failed`.

- [ ] **Step 1.6: Commit**

```bash
git add install.sh tests/test-install.sh
git commit -m "feat: add RTK install lane with arch detection, SHA256 verify, skip flag"
```

---

## Task 2: RTK Hook Registration

**Files:**
- Modify: `install.sh` — add `merge_rtk_hook()` function and call it after binary install

### Step 2.1 — Write the failing test

Add to `tests/test-install.sh` RTK block:

```bash
# Hook registration code exists in install.sh
assert_contains "${XGH_LOCAL_PACK}/install.sh" 'merge_rtk_hook'
assert_contains "${XGH_LOCAL_PACK}/install.sh" '"matcher": "Bash"'
assert_contains "${XGH_LOCAL_PACK}/install.sh" 'rtk hook --quiet'
```

- [ ] **Step 2.1:** Add hook assertions to `tests/test-install.sh`

- [ ] **Step 2.2: Run tests — verify they fail**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash tests/test-install.sh 2>&1 | grep FAIL
```

Expected: 3 FAILs for the new assertions.

### Step 2.3 — Add `merge_rtk_hook()` function to `install.sh`

Add this function near the other helper functions at the top of `install.sh` (after `warn()`/`info()` definitions):

```bash
# Merge RTK PreToolUse Bash hook into $SETTINGS_FILE using the same deep-merge
# as the main hooks block. Idempotent: deduped by command string.
merge_rtk_hook() {
  local rtk_bin="$1"
  local settings_file="$2"

  [ -z "$rtk_bin" ] && return 0
  [ -z "$settings_file" ] && return 0

  python3 -c "
import json, os, sys

rtk_bin = sys.argv[1]
settings_file = sys.argv[2]

new_entry = {
    'matcher': 'Bash',
    'hooks': [{'type': 'command', 'command': rtk_bin + ' hook --quiet'}]
}

if os.path.isfile(settings_file) and os.path.getsize(settings_file) > 0:
    data = json.load(open(settings_file))
else:
    data = {}

hooks = data.get('hooks', {})
pre = hooks.get('PreToolUse', [])

# Dedup: skip if identical command already registered
existing_cmds = {h['command'] for e in pre for h in e.get('hooks', [])}
if rtk_bin + ' hook --quiet' not in existing_cmds:
    pre.append(new_entry)

hooks['PreToolUse'] = pre
data['hooks'] = hooks
json.dump(data, open(settings_file, 'w'), indent=2)
print('RTK hook registered in ' + settings_file)
" "$rtk_bin" "$settings_file" 2>/dev/null || warn "RTK: could not register hook in ${settings_file}"
}
```

- [ ] **Step 2.3:** Add `merge_rtk_hook()` to `install.sh`

### Step 2.4 — Call `merge_rtk_hook` after binary confirm

Inside the RTK lane, immediately after the `"$_RTK_BIN" --version` confirm line, add:

```bash
  # Register PreToolUse Bash hook into same settings scope as xgh hooks
  # SETTINGS_FILE is set in section 5 (hooks scope); RTK lane runs after section 5
  # so SETTINGS_FILE is guaranteed to be set here.
  if [ -n "$_RTK_BIN" ] && [ -n "${SETTINGS_FILE:-}" ]; then
    merge_rtk_hook "$_RTK_BIN" "$SETTINGS_FILE"
  fi
```

**Important:** The RTK lane must be placed **after** section 5 (hooks) so `$SETTINGS_FILE` is already resolved. If the lane is currently before section 5, move it to after. Verify by checking that `lane "Hooking into Claude Code 🪝"` appears before `lane "Installing RTK 🗜️"` in the file.

- [ ] **Step 2.4:** Add `merge_rtk_hook` call + verify lane ordering in `install.sh`

- [ ] **Step 2.5: Run tests — verify they pass**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash tests/test-install.sh 2>&1 | tail -20
```

Expected: all pass, `0 failed`.

- [ ] **Step 2.6: Dry-run smoke test**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh 2>&1 | grep -i rtk
```

Expected: `▸ Skipping RTK (XGH_SKIP_RTK=1)` or `▸ Installing RTK 🗜️` section visible, no errors.

- [ ] **Step 2.7: Commit**

```bash
git add install.sh tests/test-install.sh
git commit -m "feat: register RTK PreToolUse Bash hook via merge_rtk_hook()"
```

---

## Task 3: `/xgh-doctor` Context Efficiency Dashboard

**Files:**
- Modify: `plugin/skills/doctor/doctor.md` — add `### Context Efficiency` section

### Step 3.1 — Read the current doctor.md output format section

Read `plugin/skills/doctor/doctor.md` and locate the `## Output format` section. The new `## Check 3b` section (use `##` heading to match all other checks) goes **before** `## Check 4 — Scheduler`.

- [ ] **Step 3.1:** Read `plugin/skills/doctor/doctor.md` to confirm insertion point

### Step 3.2 — Add the Context Efficiency section

Insert the following before `## Check 4 — Scheduler` in `plugin/skills/doctor/doctor.md`. Use `##` heading level to match the existing check headings:

````markdown
## Check 3b — Context Efficiency

Run both checks in parallel.

#### RTK — output compression

Check RTK status by running these bash commands via `ctx_execute`:

```bash
# Check binary
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

Status icons: ✅ if present/active, ❌ if missing, ⚠️ if version below `0.31.0`.

Degraded state messages:
- Binary not found + `XGH_SKIP_RTK` unset → `❌ RTK not installed — re-run install.sh (or set XGH_SKIP_RTK=1 to suppress)`
- Binary not found + `XGH_SKIP_RTK=1` → `⏭ RTK skipped (XGH_SKIP_RTK=1)`
- Version below `0.31.0` → `⚠️ RTK vX.Y.Z — upgrade to v0.31.0+ recommended`
- Binary missing but hook in settings → `❌ RTK binary missing at {path} — hook registered but inactive`
- `rtk gain` returns no data → `✅ RTK active — no Bash calls compressed yet this session`

#### context-mode — context window protection

Call the `mcp__plugin_context-mode_context-mode__ctx_stats` MCP tool (no parameters). Format its JSON output as:

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

If `ctx_stats` is unavailable (tool not found): `❌ context-mode not active — run /xgh-setup`
If `ctx_stats` returns no calls yet: `✅ context-mode active — no sandbox calls yet this session`
````

- [ ] **Step 3.2:** Add the Context Efficiency section to `plugin/skills/doctor/doctor.md`

### Step 3.3 — Update the Output format example block

In `doctor.md`, find the `## Output format` section. It contains an example output block showing what the doctor report looks like. Insert the Context Efficiency section into that example, between the connectivity/freshness block and the scheduler block:

```
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
```

- [ ] **Step 3.3:** Update output format summary table in `doctor.md` if one exists

### Step 3.4 — Smoke test (manual)

Run `/xgh-doctor` in a live Claude session and verify:
- `### Context Efficiency` section appears
- RTK subsection shows binary path or appropriate degraded message
- context-mode subsection shows ctx_stats output

- [ ] **Step 3.4:** Smoke test `/xgh-doctor` in a live session

### Step 3.5 — Commit

```bash
git add plugin/skills/doctor/doctor.md
git commit -m "feat: add Context Efficiency dashboard to /xgh-doctor (RTK + context-mode)"
```

- [ ] **Step 3.5:** Commit

---

## Task 4: Dry-Run Validation + Push

- [ ] **Step 4.1: Full test suite**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash tests/test-install.sh
```

Expected: `Results: N passed, 0 failed`

- [ ] **Step 4.2: Dry-run install smoke test**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh 2>&1
```

Expected: RTK lane appears, no errors.

- [ ] **Step 4.3: Skip flag smoke test**

```bash
XGH_SKIP_RTK=1 XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh 2>&1 | grep -i rtk
```

Expected: `▸ Skipping RTK (XGH_SKIP_RTK=1)`

- [ ] **Step 4.4: Push**

```bash
git push origin main
```
