# xgh Claude Plugin Migration — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure xgh into a Claude plugin bundle (`plugin/`) so skills and commands are auto-discovered from `~/.claude/plugins/cache/` rather than copied into individual projects, and register with a self-hosted GitHub registry.

**Architecture:** Move `skills/`, `commands/`, `hooks/`, `agents/` into a `plugin/` directory that mirrors the established Claude plugin format (e.g., superpowers). `install.sh` caches the plugin to `~/.claude/plugins/cache/tokyo-megacorp/xgh/<version>/`, writes `~/.claude/plugins/installed_plugins.json`, and still copies hooks to `~/.claude/hooks/` + registers them in `~/.claude/settings.json`. Per-project setup moves entirely to `/xgh-init`, which gains a dependency check and stale-install cleanup.

**Tech Stack:** Bash, Python 3 (for JSON manipulation), Claude plugin format (installed_plugins.json v2), launchd (macOS), cron/systemd (Linux).

---

## Critical Context

**Skills/commands/agents**: Claude Code auto-discovers these from the plugin `installPath` — no explicit registration in `~/.claude/` needed; only `installed_plugins.json` entry required.

**Hooks**: NOT auto-discovered. Must be copied to `~/.claude/hooks/` with `xgh-` prefix and registered in `~/.claude/settings.json`. This behavior is unchanged — hooks are already installed at user-global scope.

**Hook filenames:**
- In `plugin/hooks/`: `session-start.sh`, `prompt-submit.sh` (no prefix)
- In `~/.claude/hooks/`: `xgh-session-start.sh`, `xgh-prompt-submit.sh` (prefix added by install.sh)

**`installed_plugins.json` v2 schema** (real format, from existing installs):

```json
{
  "version": 2,
  "plugins": {
    "xgh@tokyo-megacorp": [
      {
        "scope": "user",
        "installPath": "/Users/<user>/.claude/plugins/cache/tokyo-megacorp/xgh/1.0.0",
        "version": "1.0.0",
        "installedAt": "2026-03-16T00:00:00.000Z",
        "lastUpdated": "2026-03-16T00:00:00.000Z",
        "gitCommitSha": "<sha>"
      }
    ]
  }
}
```

Note: each plugin key maps to an **array** of entries (not a plain object). `installedAt` is preserved on upgrades; only `lastUpdated` and `gitCommitSha` change.

**Plugin version**: defined in `plugin/gemini-extension.json`. Start at `1.0.0`.

**`agents/`**: included in the plugin (not in original spec — spec was corrected). Move `agents/` → `plugin/agents/`.

---

## File Map

| Action | Path |
|--------|------|
| Create | `plugin/gemini-extension.json` |
| Create | `plugin/README.md` |
| git mv | `skills/` → `plugin/skills/` |
| git mv | `commands/` → `plugin/commands/` |
| git mv | `hooks/` → `plugin/hooks/` |
| git mv | `agents/` → `plugin/agents/` |
| Modify | `techpack.yaml` — update skills/hooks/commands/agents paths |
| Modify | `install.sh` — remove per-project file-copy section; add `register_plugin()` |
| Modify | `uninstall.sh` — add `deregister_plugin()` |
| Modify | `plugin/skills/init/init.md` — add dependency check + stale cleanup |
| Modify | `tests/test-install.sh` — update assertions for plugin structure |
| Modify | `tests/test-uninstall.sh` — update assertions for plugin deregistration |

---

## Chunk 1: Plugin Directory Structure

### Task 1: Write failing tests for plugin structure

**Files:**
- Modify: `tests/test-install.sh`

- [ ] **Step 1: Add plugin structure assertions to test-install.sh**

Open `tests/test-install.sh`. After the existing `assert_dir_exists` calls (around line 54), add:

```bash
# Plugin structure
assert_file_exists "plugin/gemini-extension.json"
assert_file_exists "plugin/README.md"
assert_dir_exists  "plugin/skills"
assert_dir_exists  "plugin/commands"
assert_dir_exists  "plugin/hooks"
assert_dir_exists  "plugin/agents"
assert_file_exists "plugin/skills/init/init.md"
assert_file_exists "plugin/commands/init.md"
assert_file_exists "plugin/hooks/session-start.sh"
assert_file_exists "plugin/agents/collaboration-dispatcher.md"
assert_contains    "plugin/gemini-extension.json" '"name": "xgh"'
assert_contains    "plugin/gemini-extension.json" '"version"'
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bash tests/test-install.sh 2>&1 | grep "FAIL"
```

Expected: multiple `FAIL: plugin/... missing` lines.

---

### Task 2: Create plugin manifest and README

**Files:**
- Create: `plugin/gemini-extension.json`
- Create: `plugin/README.md`

- [ ] **Step 1: Create plugin directory and gemini-extension.json**

```bash
mkdir -p plugin
```

Create `plugin/gemini-extension.json`:

```json
{
  "name": "xgh",
  "description": "Persistent memory and team context for AI-assisted development",
  "version": "1.0.0"
}
```

- [ ] **Step 2: Create plugin/README.md**

Create `plugin/README.md`:

```markdown
# xgh Plugin

Persistent memory and team context for AI-assisted development.

## Install

Full install (includes Qdrant + inference backend):

```bash
curl -fsSL https://raw.githubusercontent.com/tokyo-megacorp/xgh/main/install.sh | bash
```

Lite install (assumes infra already running):

```
/plugin install github:tokyo-megacorp/xgh
```

## Per-project setup

Run once inside any repo:

```
/xgh-init
```
```

- [ ] **Step 3: Run task 1 tests — plugin structure assertions should now partially pass**

```bash
bash tests/test-install.sh 2>&1 | grep -E "FAIL.*plugin/gemini|FAIL.*plugin/README"
```

Expected: these two now pass; skills/commands/hooks/agents still fail.

- [ ] **Step 4: Commit scaffolding**

```bash
git add plugin/
git commit -m "feat: add plugin/ directory with gemini-extension.json and README"
```

---

### Task 3: Move skills/ → plugin/skills/

- [ ] **Step 1: Move with git mv to preserve history**

```bash
git mv skills plugin/skills
```

- [ ] **Step 2: Verify all skill dirs are present**

```bash
ls plugin/skills/
```

Expected: `analyze  ask  briefing  calibrate  collab  curate  design  doctor  implement  index  init  investigate  knowledge-handoff  mcp-setup  pr-context-bridge  profile  retrieve  team  todo-killer  track`

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor: move skills/ → plugin/skills/"
```

---

### Task 4: Move commands/ → plugin/commands/

- [ ] **Step 1: Move**

```bash
git mv commands plugin/commands
```

- [ ] **Step 2: Verify**

```bash
ls plugin/commands/
```

Expected: `analyze.md  ask.md  brief.md  briefing.md  calibrate.md  collab.md  curate.md  design.md  doctor.md  help.md  implement.md  index.md  init.md  investigate.md  profile.md  retrieve.md  setup.md  status.md  todo-killer.md  track.md  xgh-collaborate.md`

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor: move commands/ → plugin/commands/"
```

---

### Task 5: Move hooks/ → plugin/hooks/

- [ ] **Step 1: Move**

```bash
git mv hooks plugin/hooks
```

- [ ] **Step 2: Verify filenames (no xgh- prefix in source)**

```bash
ls plugin/hooks/
```

Expected: `session-start.sh  prompt-submit.sh` (and any other hook files like `cipher-pre-hook.sh`, `cipher-post-hook.sh`)

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor: move hooks/ → plugin/hooks/"
```

---

### Task 6: Move agents/ → plugin/agents/

- [ ] **Step 1: Move**

```bash
git mv agents plugin/agents
```

- [ ] **Step 2: Verify**

```bash
ls plugin/agents/
```

Expected: `collaboration-dispatcher.md  code-reviewer.md`

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor: move agents/ → plugin/agents/"
```

---

### Task 7: Update techpack.yaml paths

**Files:**
- Modify: `techpack.yaml`

- [ ] **Step 1: Find all path references to the moved directories**

```bash
grep -n "skills\|commands\|hooks\|agents" techpack.yaml
```

Note every line that references these directories.

- [ ] **Step 2: Update all path references to use plugin/ prefix**

For every occurrence of `skills/`, `commands/`, `hooks/`, `agents/` that references the source directories, update to `plugin/skills/`, `plugin/commands/`, `plugin/hooks/`, `plugin/agents/`.

- [ ] **Step 3: Verify no stale root-level paths remain**

```bash
grep -nE "^\s*(skills|commands|hooks|agents)/" techpack.yaml
```

Expected: no output (all paths now start with `plugin/`).

Note: `techpack.yaml` path correctness is validated by `tests/test-techpack.sh`. Run it:

```bash
bash tests/test-techpack.sh 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add techpack.yaml
git commit -m "refactor: update techpack.yaml paths to plugin/ subdirectories"
```

---

### Task 8: Run Chunk 1 structure tests

- [ ] **Step 1: Run test-install.sh structure assertions**

```bash
bash tests/test-install.sh 2>&1 | grep -E "FAIL.*plugin"
```

Expected: no `FAIL` lines for plugin structure assertions. (Registration assertions added in Chunk 2 will still fail — that's expected.)

---

## Chunk 2: install.sh — Plugin Registration

### Task 9: Add register_plugin() function to install.sh

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Write failing tests for plugin registration**

Add to `tests/test-install.sh`:

```bash
# Plugin registration in installed_plugins.json
PLUGINS_JSON="${HOME}/.claude/plugins/installed_plugins.json"
assert_file_exists "$PLUGINS_JSON"
assert_contains    "$PLUGINS_JSON" '"xgh@tokyo-megacorp"'
assert_contains    "$PLUGINS_JSON" '"scope": "user"'
# Plugin cache populated
assert_dir_exists  "${HOME}/.claude/plugins/cache/tokyo-megacorp/xgh"
assert_file_exists "${HOME}/.claude/plugins/cache/tokyo-megacorp/xgh/1.0.0/gemini-extension.json"
assert_dir_exists  "${HOME}/.claude/plugins/cache/tokyo-megacorp/xgh/1.0.0/skills"
assert_dir_exists  "${HOME}/.claude/plugins/cache/tokyo-megacorp/xgh/1.0.0/commands"
```

- [ ] **Step 2: Run to confirm failure**

```bash
bash tests/test-install.sh 2>&1 | grep "FAIL.*plugin\|FAIL.*installed"
```

Expected: failures about `installed_plugins.json` and cache dirs.

- [ ] **Step 3: Add register_plugin() function to install.sh**

Find the block of functions in `install.sh` (after the helper functions, before the main execution flow). Add this function:

```bash
# ── Plugin Registration ────────────────────────────────────
register_plugin() {
  local plugin_name="xgh"
  local registry="tokyo-megacorp"
  local registry_key="${plugin_name}@${registry}"

  # Read version from gemini-extension.json
  local version
  version=$(python3 -c "
import json, sys
try:
    d = json.load(open('${PACK_DIR}/plugin/gemini-extension.json'))
    print(d['version'])
except Exception as e:
    print('1.0.0', file=sys.stderr)
    print('1.0.0')
" 2>/dev/null || echo "1.0.0")

  local cache_dir="${HOME}/.claude/plugins/cache/${registry}/${plugin_name}"
  local install_path="${cache_dir}/${version}"
  local plugins_json="${HOME}/.claude/plugins/installed_plugins.json"

  local git_sha
  git_sha=$(git -C "${PACK_DIR}" rev-parse HEAD 2>/dev/null || echo "unknown")

  local now
  now=$(python3 -c "
from datetime import datetime, timezone
print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z'))
")

  lane "Registering xgh plugin 🔌"
  info "Plugin version: ${version}"
  info "Cache path: ${install_path}"

  # Copy plugin/ contents to versioned cache directory (idempotent — overwrites on re-install)
  mkdir -p "${install_path}"
  cp -r "${PACK_DIR}/plugin/." "${install_path}/"

  # Write registration entry (preserves installedAt from previous install)
  python3 - <<PYEOF
import json, os

plugins_file = "${plugins_json}"
registry_key = "${registry_key}"
install_path = "${install_path}"
version = "${version}"
git_sha = "${git_sha}"
now = "${now}"

# Read existing file or start fresh
try:
    with open(plugins_file) as f:
        data = json.load(f)
except Exception:
    data = {"version": 2, "plugins": {}}

# Preserve installedAt from existing entry if present
existing = data.get("plugins", {}).get(registry_key, [])
installed_at = existing[0].get("installedAt", now) if existing else now

data.setdefault("plugins", {})[registry_key] = [{
    "scope": "user",
    "installPath": install_path,
    "version": version,
    "installedAt": installed_at,
    "lastUpdated": now,
    "gitCommitSha": git_sha
}]

os.makedirs(os.path.dirname(plugins_file), exist_ok=True)
with open(plugins_file, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("✓ Registered xgh@tokyo-megacorp in installed_plugins.json")
PYEOF

  # Detect old-style per-project skill copies and warn
  local old_found=false
  for d in "${HOME}/.claude/skills/xgh-"* ".claude/skills/xgh-"*; do
    [ -d "$d" ] && old_found=true && break
  done
  if $old_found; then
    info "Legacy per-project skill copies detected — /xgh-init will clean them up on next run"
  fi

  info "Plugin registered ✓"
}
```

- [ ] **Step 4: Call register_plugin() in the install flow**

Find where `install.sh` calls the install steps in sequence (look for the block that calls functions like the skills/commands section — near line 1560). Add `register_plugin` **after** the hooks registration step and **instead of** (replacing) the skills/commands/agents copy block.

Before this change you should see something like:
```bash
# ... hooks setup ...
# ── 7. Skills + Commands + Agents ─────
lane "Teaching the horse new tricks 🎓"
...
```

Replace section 7 with:
```bash
# ── 7. Plugin Registration ─────────────
register_plugin
```

- [ ] **Step 5: Run install dry-run and check registration output**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh 2>&1 | grep -E "Plugin|plugin|Registered"
```

Expected output includes:
```
Registering xgh plugin 🔌
Plugin version: 1.0.0
✓ Registered xgh@tokyo-megacorp in installed_plugins.json
Plugin registered ✓
```

- [ ] **Step 6: Run tests**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh && bash tests/test-install.sh 2>&1 | tail -5
```

Expected: `FAIL: 0`

- [ ] **Step 7: Commit**

```bash
git add install.sh tests/test-install.sh
git commit -m "feat: add register_plugin() — cache plugin to ~/.claude/plugins, remove per-project skill copies"
```

---

### Task 10: Remove stale assertions from test-install.sh

**Files:**
- Modify: `tests/test-install.sh`

- [ ] **Step 1: Find and remove assertions that checked per-project skill copies**

```bash
grep -n "\.claude/skills\|\.claude/commands" tests/test-install.sh
```

Remove lines like:
```bash
assert_dir_exists ".claude/skills"
assert_dir_exists ".claude/commands"
```

These are no longer valid — skills/commands live in the plugin cache.

- [ ] **Step 2: Verify hooks assertions still exist (unchanged behavior)**

```bash
grep -n "hooks" tests/test-install.sh
```

Expected: still asserts `${HOME}/.claude/hooks/xgh-session-start.sh` exists (hooks are still user-global, copied by install.sh).

- [ ] **Step 3: Run full test suite**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh && bash tests/test-install.sh 2>&1 | tail -3
```

Expected: `PASS: N, FAIL: 0`

- [ ] **Step 4: Commit**

```bash
git add tests/test-install.sh
git commit -m "test: remove stale per-project skill copy assertions from test-install.sh"
```

---

## Chunk 3: uninstall.sh + Deregistration

### Task 11: Add plugin deregistration to uninstall.sh

**Files:**
- Modify: `uninstall.sh`
- Modify: `tests/test-uninstall.sh`

- [ ] **Step 1: Check if assert_not_exists or assert_no_dir helper already exists**

```bash
grep -n "assert_not\|assert_no_dir\|assert_no_file" tests/test-uninstall.sh | head -5
```

If an equivalent exists, use it. If not, add `assert_no_dir` to `tests/test-uninstall.sh`:

```bash
assert_no_dir() {
  if [ ! -d "$1" ]; then PASS=$((PASS + 1)); else echo "FAIL: dir $1 should not exist after uninstall"; FAIL=$((FAIL + 1)); fi
}
```

- [ ] **Step 2: Write failing test for plugin deregistration**

Add to `tests/test-uninstall.sh` (after uninstall runs):

```bash
# Plugin deregistration
PLUGINS_JSON="${HOME}/.claude/plugins/installed_plugins.json"
if [ -f "$PLUGINS_JSON" ]; then
  if grep -q '"xgh@tokyo-megacorp"' "$PLUGINS_JSON"; then
    echo "FAIL: xgh@tokyo-megacorp still in installed_plugins.json after uninstall"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: xgh@tokyo-megacorp removed from installed_plugins.json"
    PASS=$((PASS + 1))
  fi
fi
assert_no_dir "${HOME}/.claude/plugins/cache/tokyo-megacorp/xgh"
```

- [ ] **Step 3: Run to confirm failure**

```bash
bash tests/test-uninstall.sh 2>&1 | grep "FAIL"
```

Expected: failures about `xgh@tokyo-megacorp` still present.

- [ ] **Step 4: Read uninstall.sh to find insertion point**

```bash
grep -n "lane\|info\|rm -f\|function" uninstall.sh | head -30
```

- [ ] **Step 5: Add deregister_plugin() function to uninstall.sh**

```bash
deregister_plugin() {
  local plugins_json="${HOME}/.claude/plugins/installed_plugins.json"
  local cache_dir="${HOME}/.claude/plugins/cache/tokyo-megacorp/xgh"

  # Remove from installed_plugins.json
  if [ -f "$plugins_json" ]; then
    python3 - <<PYEOF
import json, os

plugins_file = "${plugins_json}"
try:
    with open(plugins_file) as f:
        data = json.load(f)
    data.get("plugins", {}).pop("xgh@tokyo-megacorp", None)
    with open(plugins_file, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print("✓ Removed xgh@tokyo-megacorp from installed_plugins.json")
except Exception as e:
    print(f"⚠ Could not update installed_plugins.json: {e}")
PYEOF
  fi

  # Remove all cached plugin versions
  if [ -d "$cache_dir" ]; then
    rm -rf "$cache_dir"
    echo "✓ Removed plugin cache at ${cache_dir}"
  fi
}
```

Call `deregister_plugin` early in the uninstall flow (before or alongside existing cleanup steps).

- [ ] **Step 6: Run uninstall tests**

```bash
bash tests/test-uninstall.sh 2>&1 | tail -5
```

Expected: `FAIL: 0`

- [ ] **Step 7: Commit**

```bash
git add uninstall.sh tests/test-uninstall.sh
git commit -m "feat: add deregister_plugin() to uninstall.sh, update uninstall tests"
```

---

## Chunk 4: /xgh-init Skill Updates

### Task 12: Add dependency check and stale cleanup to init skill

**Files:**
- Modify: `plugin/skills/init/init.md`

- [ ] **Step 1: Read current init skill content**

```bash
cat plugin/skills/init/init.md
```

Note the existing structure (tasks, steps it currently performs).

- [ ] **Step 2: Add dependency check section at the top of the skill**

In `plugin/skills/init/init.md`, insert a "Dependency Check" section before the scaffolding steps. This section instructs Claude (the AI) what to check and how to respond:

```markdown
## Step 0: Dependency Check (run before scaffolding)

Check each dependency below. Respond per the instructions for each result.

### Cipher MCP
Run in Bash: `claude mcp list 2>/dev/null | grep -i cipher`
- **Found** → continue
- **Not found** → run `claude mcp add -s user cipher ~/.local/bin/cipher-mcp` and report: "Auto-configured Cipher MCP."

### Qdrant
Run in Bash: `curl -sf --max-time 3 "${QDRANT_URL:-http://localhost:6333}/healthz"`
- **Responds** → continue
- **Unreachable** → report: "Qdrant is not running. To fix: run `install.sh` to install it locally, or set `XGH_BACKEND=remote` and `XGH_REMOTE_URL=<url>` to use a remote endpoint."

### Inference backend
Run in Bash: `curl -sf --max-time 3 "${XGH_REMOTE_URL:-http://localhost:11434}/v1/models"`
- **Responds** → continue
- **Unreachable** → report: "Inference backend not running. To fix: run `install.sh` to install vllm-mlx (macOS) or Ollama (Linux), or set `XGH_BACKEND=remote`."

### Partial mode (all three checks fail)
Proceed with scaffolding anyway. After completing, tell the user:
> "xgh memory tools are not yet configured — context tree scaffolded successfully. Run `install.sh` or `/plugin install github:tokyo-megacorp/xgh` to complete setup. Cipher search will not work until backends are running."
```

- [ ] **Step 3: Add stale install cleanup section**

After the dependency check section, add:

```markdown
## Step 0b: Stale Install Cleanup

Check for old-style per-project skill copies from pre-plugin installs:

Run in Bash:
```bash
ls .claude/skills/ 2>/dev/null | grep "^xgh-"
ls .claude/commands/ 2>/dev/null | grep "^xgh-"
```

If any `xgh-*` entries are found:
1. Remove them:
   ```bash
   rm -rf .claude/skills/xgh-* .claude/commands/xgh-* 2>/dev/null || true
   ```
2. Report: "Removed legacy per-project skill copies. Skills now load from the user-level plugin at `~/.claude/plugins/cache/tokyo-megacorp/xgh/`."

If none found → continue silently.
```

- [ ] **Step 4: Commit**

```bash
git add plugin/skills/init/init.md
git commit -m "feat: add dependency check and stale-install cleanup to /xgh-init skill"
```

---

## Chunk 5: Final Verification

### Task 13: Run all test suites

- [ ] **Step 1: Full install dry-run**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh 2>&1 | tail -20
```

Expected: no errors, plugin registration shown.

- [ ] **Step 2: All test suites**

```bash
bash tests/test-install.sh 2>&1 | tail -3
bash tests/test-config.sh  2>&1 | tail -3
bash tests/test-techpack.sh 2>&1 | tail -3
bash tests/test-uninstall.sh 2>&1 | tail -3
```

Expected: all `FAIL: 0`.

- [ ] **Step 3: Verify plugin cache structure**

```bash
ls ~/.claude/plugins/cache/tokyo-megacorp/xgh/1.0.0/
```

Expected: `README.md  agents  commands  gemini-extension.json  hooks  skills`

- [ ] **Step 4: Verify installed_plugins.json**

```bash
python3 -c "
import json
d = json.load(open('${HOME}/.claude/plugins/installed_plugins.json'))
entry = d['plugins'].get('xgh@tokyo-megacorp', [{}])[0]
print('scope:', entry.get('scope'))
print('version:', entry.get('version'))
print('installPath:', entry.get('installPath'))
"
```

Expected:
```
scope: user
version: 1.0.0
installPath: /Users/<you>/.claude/plugins/cache/tokyo-megacorp/xgh/1.0.0
```

- [ ] **Step 5: Verify no per-project skill copies in current project**

```bash
ls .claude/skills/ 2>/dev/null | grep "^xgh-" && echo "FAIL: stale copies" || echo "✓ No per-project skill copies"
ls .claude/commands/ 2>/dev/null | grep "^xgh-" && echo "FAIL: stale copies" || echo "✓ No per-project command copies"
```

- [ ] **Step 6: Final commit and tag**

```bash
git add -A
git status  # verify nothing unexpected staged
git commit -m "feat: xgh v1.0.0 — Claude plugin migration complete"
git tag v1.0.0
```
