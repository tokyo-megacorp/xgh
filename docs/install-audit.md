# install.sh Comprehensive Audit

**File**: `/Users/pedro/Developer/xgh/install.sh` (1285 lines)
**Date**: 2026-03-16

---

## 1. Bugs & Gaps

### BUG-1: `set -e` causes silent abort on any intermediate failure (CRITICAL)
**Lines**: 2, entire file
**Severity**: Critical | **Effort**: Medium

`set -euo pipefail` on line 2 means ANY unguarded command failure kills the installer silently. Multiple sections rely on `||` guards, but several do not:

- **Line 40**: Homebrew install failure aborts the entire script. No `|| { error "..."; exit 1; }` guard.
- **Line 64**: `uv tool install` for vllm-mlx has no fallback. If the git repo is unreachable, the installer dies mid-way.
- **Line 592**: `git clone` for the pack has no error guard; if the network is down after dependencies installed, the user is left in a half-installed state.
- **Line 1236-1239**: `cp` commands for lib helpers will abort if any source file is missing from the pack. No existence check like the hook section has.

### BUG-2: Python code injection via RESOLVED_HOOKS variable (HIGH)
**Lines**: 856-864, 868-899
**Severity**: High | **Effort**: Small

The settings merge uses Python with triple-quoted f-strings that interpolate `$RESOLVED_HOOKS` directly into Python source:
```python
hooks_data = json.loads('''${RESOLVED_HOOKS}''')
```
If `RESOLVED_HOOKS` contains a triple-quote sequence (`'''`), the Python code breaks or could execute arbitrary code. The `HOOKS_CMD_PREFIX` on lines 670/675 is user-controllable (derived from `$HOME` or `$PWD`). While unlikely in practice, it is a textbook injection vector.

**Fix**: Write `RESOLVED_HOOKS` to a temp file and `json.load(open(tmpfile))` instead.

### BUG-3: Race condition in Qdrant collection creation (MEDIUM)
**Lines**: 548-571
**Severity**: Medium | **Effort**: Trivial

The check `curl -sf "${qdrant_url}/collections/${collection}"` followed by the PUT to create the collection is a classic TOCTOU race. If two installers run simultaneously (or the user re-runs quickly), the collection could be created between the check and the creation attempt. Not dangerous since Qdrant returns an error on duplicate creation, but the error message is swallowed by `2>/dev/null`.

### BUG-4: Vector dimension hardcoded to 768 despite model choice (HIGH)
**Lines**: 530, 559-566, 627
**Severity**: High | **Effort**: Small

The installer hardcodes `dimensions: 768` everywhere (cipher.yml line 530, Qdrant collections line 559, mcp.json line 627). But the model list on line 95 includes `all-MiniLM-L6-v2-4bit` which produces **384-dimensional** vectors. If the user selects this model, embeddings will be 384-dim but stored in 768-dim collections, causing silent failures or zero-padded garbage vectors.

**Fix**: Map each embed model to its dimension in the model list and propagate the value.

### BUG-5: Broken `sed` for connected MCPs JSON array (MEDIUM)
**Lines**: 1179
**Severity**: Medium | **Effort**: Small

```bash
echo "$CONNECTED_MCPS" | sed 's/,$//' | sed 's/\([^,]*\)/"\1"/g' | sed 's/,/, /g'
```
This sed pipeline fails if MCP names contain special regex characters (parentheses, dots, etc.), and produces malformed JSON if `CONNECTED_MCPS` is empty (resulting in `[""]` instead of `[]`). When empty, line 1169 tries to handle it but the `cat` heredoc on line 1176 still runs.

### BUG-6: `XGH_DRY_RUN` check is redundant/dead code (LOW)
**Lines**: 1254-1258
**Severity**: Low | **Effort**: Trivial

Line 1254 checks `XGH_DRY_RUN -eq 0` inside a block that is already guarded by the same check on line 1225. The `else` branch on line 1256-1258 is dead code.

### BUG-7: Hooks file naming mismatch (HIGH)
**Lines**: 682-696 vs hooks-settings.json
**Severity**: High | **Effort**: Small

The installer copies hooks to `xgh-${hook}.sh` (line 684), producing names like `xgh-session-start.sh` and `xgh-prompt-submit.sh`. The hooks-settings.json references `xgh-session-start.sh` and `xgh-prompt-submit.sh`. However, the loop iterates `session-start` and `prompt-submit` (line 682), and the source files are `hooks/session-start.sh` and `hooks/prompt-submit.sh`. This works, but any future hook name containing characters that differ between the iteration variable and the template would break silently.

### BUG-8: `CLAUDE.local.md` marker check uses wrong substring (MEDIUM)
**Lines**: 1079
**Severity**: Medium | **Effort**: Trivial

The check `grep -q "mcs:begin xgh"` but the marker written is `<!-- mcs:begin xgh.instructions -->`. This works today because the grep matches the substring, but if someone manually adds a comment containing `mcs:begin xgh-something-else`, the installer would wrongly skip injection.

---

## 2. UX Improvements

### UX-1: No spinner or progress indicator for long operations (MEDIUM)
**Severity**: Medium | **Effort**: Medium

Lines 217-227 (model download), 40 (Homebrew install), 64 (vllm-mlx install), 239 (Cipher npm install) are long-running operations with no progress feedback. Best-in-class installers (rustup, starship) show animated spinners. The model download section says "grab a coffee" but shows nothing while multi-GB downloads happen.

### UX-2: No timing information (LOW)
**Severity**: Low | **Effort**: Small

The installer shows no elapsed time per phase or total. rustup and homebrew show time taken. Adding `SECONDS` tracking per lane would help.

### UX-3: No `--help` or `--version` flags (MEDIUM)
**Severity**: Medium | **Effort**: Small

The script accepts no arguments. Running `bash install.sh --help` triggers `set -u` and fails. There should be argument parsing for `--help`, `--version`, `--yes` (non-interactive), `--verbose`, `--quiet`, `--dry-run`.

### UX-4: No Ctrl+C cleanup handler (HIGH)
**Severity**: High | **Effort**: Small

There is no `trap` for `SIGINT`/`SIGTERM`. If the user Ctrl+C's mid-install, partially written config files (cipher.yml, mcp.json, settings.json) may be left in a corrupt state. Best practice: write to tempfiles, then `mv` atomically, with a trap that cleans up temps.

### UX-5: No non-interactive mode for CI/automation (MEDIUM)
**Severity**: Medium | **Effort**: Small

Lines 157, 188, 655, 1130, 1145 all use `read -r -p`. In a non-interactive context (piped stdin, CI), these either hang or read empty. There is no `--yes` or `XGH_NONINTERACTIVE=1` mode. The `XGH_DRY_RUN` partially addresses this but skips ALL real work. You need a separate "accept all defaults" flag.

### UX-6: Color output not disabled when stdout is not a terminal (LOW)
**Severity**: Low | **Effort**: Trivial

Lines 16-22 define colors unconditionally. When piped (`bash install.sh 2>&1 | tee log`), ANSI escapes pollute the output. Best practice: `if [[ -t 1 ]]; then ... else RED=''; ... fi` or respect `NO_COLOR` env var.

### UX-7: No summary of what changed (MEDIUM)
**Severity**: Medium | **Effort**: Small

The final "next steps" section (lines 1262-1284) lists what to do next but not what was actually installed or modified. Best-in-class installers (homebrew, rustup) print a diff summary: "Created 5 files, modified 2, installed 3 packages".

### UX-8: No uninstall story (MEDIUM)
**Severity**: Medium | **Effort**: Medium

There is no `uninstall.sh` mentioned in the installer output. The test suite has `test-uninstall.sh` but users aren't told about it. Best practice: print "To uninstall: bash uninstall.sh" in the final banner, and/or install an `xgh uninstall` command.

---

## 3. Missing Features

### FEAT-1: No version pinning or upgrade path (HIGH)
**Severity**: High | **Effort**: Medium

`XGH_VERSION` is defined on line 4 but never used anywhere in the script. There is no mechanism to:
- Pin to a specific version/tag of the pack
- Check current version vs available version
- Upgrade in place (the `git pull` on line 590 is the closest, but it always pulls latest)
- Roll back to a previous version

### FEAT-2: No health check after install (HIGH)
**Severity**: High | **Effort**: Small

The installer finishes without verifying anything works. It should:
- Check that `cipher-mcp` wrapper is executable and runs
- Verify Qdrant is reachable (if installed)
- Verify the embedding model responds to a test request
- Check that `mcp.json` is valid JSON
- Validate that `settings.json` is valid JSON

### FEAT-3: No backup before overwriting configs (MEDIUM)
**Severity**: Medium | **Effort**: Small

The installer overwrites `mcp.json` (line 613) unconditionally on every run. If the user had custom MCP servers configured, they are silently destroyed. Similarly, `settings.json` merging (lines 866-899) can corrupt existing settings if the Python merge fails (it falls through to the warn on line 881 but the file may already be partially written).

**Fix**: `cp "$file" "$file.bak.$(date +%s)"` before overwriting.

### FEAT-4: No platform detection or guards (CRITICAL)
**Severity**: Critical | **Effort**: Medium

The script:
- Assumes macOS (uses `brew`, line 38-41)
- Assumes Apple Silicon (installs `vllm-mlx` which only works on Apple Silicon, line 62-65)
- Uses macOS-specific `launchd` plists (line 1248-1249)
- Never checks `uname -s` or `uname -m`

Running on Linux or Intel Mac will fail in confusing ways. At minimum, the script should detect the platform at the top and either adapt or exit with a clear message.

### FEAT-5: No shell profile integration (LOW)
**Severity**: Low | **Effort**: Small

The `cipher-mcp` wrapper is installed to `~/.local/bin/` (line 250) which may not be in the user's `$PATH`. The installer never checks or offers to add it. Compare with rustup which modifies `.zshrc`/`.bashrc`.

### FEAT-6: No telemetry opt-in/out (LOW)
**Severity**: Low | **Effort**: Small

Not necessarily needed, but worth noting that best-in-class installers (homebrew, starship) have explicit telemetry policies. The `usage-tracker.sh` (line 1238) is installed without explaining what it tracks.

### FEAT-7: No offline/airgapped install support (MEDIUM)
**Severity**: Medium | **Effort**: Large

The installer requires internet for: Homebrew, Node.js, Python, uv, vllm-mlx, cipher npm, HuggingFace models, git clone of the pack. There is no way to provide these as local artifacts. The `XGH_LOCAL_PACK` helps for the pack itself, but not for dependencies.

### FEAT-8: No idempotent `mcp.json` merging (HIGH)
**Severity**: High | **Effort**: Small

Line 613 `cat > "${CLAUDE_DIR}/mcp.json"` overwrites the entire file. If the user had other MCP servers (GitHub, Postgres, etc.) configured in `mcp.json`, they are destroyed. The settings merge in section 6 does a proper merge, but `mcp.json` does not.

**Fix**: Read existing `mcp.json`, merge the `cipher` key, write back.

---

## 4. Robustness

### ROB-1: Linux support (CRITICAL)
**Severity**: Critical | **Effort**: Large

Running on Linux:
- Line 38-40: Tries to install Homebrew (works on Linux but unusual)
- Line 62-65: Installs `vllm-mlx` which requires Apple MLX framework -- will fail
- Lines 1248-1249: Copies macOS `launchd` plist files; should use `systemd` on Linux
- No `apt`/`dnf` alternatives for package installation

### ROB-2: Intel Mac support (HIGH)
**Severity**: High | **Effort**: Medium

On Intel Mac:
- Line 62-65: `vllm-mlx` requires Apple Silicon (M1+). Installation will succeed via pip but the binary will crash at runtime with `Illegal instruction`.
- All MLX models (lines 85-96) require Apple Silicon.
- No detection, no fallback (e.g., suggesting ollama or llama.cpp instead).

### ROB-3: No internet mid-install (MEDIUM)
**Severity**: Medium | **Effort**: Small

Scenario: User has brew/node/python installed, internet drops before model download.
- Line 217-227: Model download fails, caught by `|| warn` -- OK, graceful.
- Line 239: npm install fails, caught by error handler -- OK.
- Line 592: `git clone` of pack fails -- **NOT caught**, `set -e` kills the script with no explanation.

### ROB-4: Disk full (LOW)
**Severity**: Low | **Effort**: Small

If disk is full during model download (multi-GB), `huggingface_hub.snapshot_download` will fail with a Python traceback. The outer `|| warn` catches it, but the partial download artifacts remain and may not be cleaned up. On next run, `_model_cached` (line 80-83) checks for the directory's existence, not completeness -- a partially downloaded model will be treated as "cached" and skipped.

### ROB-5: brew/npm/uv commands hang (MEDIUM)
**Severity**: Medium | **Effort**: Small

No timeouts on external commands. If `brew install node` hangs (e.g., waiting for a Xcode license agreement), the installer hangs forever. Best practice: `timeout 300 brew install node` or at least document that Ctrl+C is safe (which it isn't, per UX-4).

### ROB-6: Python 3 is assumed for settings merge even in dry run (LOW)
**Severity**: Low | **Effort**: Trivial

The dry-run path (line 573-577) skips dependency installation, but sections 6 (lines 856-935) run unconditionally and require `python3`. If a user runs `XGH_DRY_RUN=1` without Python 3 installed, the script will fail.

Actually -- looking more carefully, the dry-run skipping is only in the big `if` block (lines 35-577). Sections 4-12 run regardless of dry run. But many of them need python3 (settings merge), curl (Qdrant), etc. that would only be installed in the non-dry-run path.

### ROB-7: `XGH_LOCAL_PACK=.` with relative paths (MEDIUM)
**Severity**: Medium | **Effort**: Trivial

Line 582 sets `PACK_DIR="$XGH_LOCAL_PACK"`. If the user does `XGH_LOCAL_PACK=.`, this becomes `PACK_DIR="."`. Later, if any `cd` were to happen (none do currently), paths would break. More importantly, on line 1197 `SCRIPTS_DIR="${PACK_DIR}/scripts"` and on line 1200 the generated script hardcodes this relative path. The final "Next steps" on line 1277 prints `bash ./scripts/start-models.sh` which only works from the repo root.

---

### FEAT-9: vllm-mlx not daemonized — model server requires manual start (HIGH)
**Severity**: High | **Effort**: Small

The retriever and analyzer agents are installed as launchd/cron daemons, but `vllm-mlx` (the model server) is not. The user must manually run `bash start-models.sh` every time. If vllm-mlx isn't running, Cipher's embedding calls silently fail against `localhost:11434`. The model server should be a launchd agent like the ingest schedulers, with a corresponding plist template.

---

## Prioritized Action List

| # | Finding | Severity | Effort | Priority |
|---|---------|----------|--------|----------|
| 1 | FEAT-4: No platform detection | Critical | Medium | P0 |
| 2 | BUG-4: Hardcoded 768 dims with 384-dim model option | High | Small | P0 |
| 3 | FEAT-8: `mcp.json` overwritten, destroys user config | High | Small | P0 |
| 4 | UX-4: No Ctrl+C cleanup handler | High | Small | P0 |
| 5 | FEAT-9: vllm-mlx not daemonized | High | Small | P0 |
| 5 | BUG-1: `set -e` causes silent mid-install abort | Critical | Medium | P1 |
| 6 | FEAT-1: `XGH_VERSION` unused, no upgrade path | High | Medium | P1 |
| 7 | FEAT-2: No post-install health check | High | Small | P1 |
| 8 | BUG-2: Python code injection via triple-quotes | High | Small | P1 |
| 9 | UX-5: No non-interactive mode | Medium | Small | P1 |
| 10 | FEAT-3: No backup before overwriting configs | Medium | Small | P1 |
| 11 | UX-3: No --help flag | Medium | Small | P2 |
| 12 | BUG-5: Broken sed for MCPs JSON array | Medium | Small | P2 |
| 13 | UX-1: No spinners for long operations | Medium | Medium | P2 |
| 14 | UX-7: No summary of changes made | Medium | Small | P2 |
| 15 | UX-8: No uninstall guidance in output | Medium | Medium | P2 |
| 16 | ROB-5: No timeouts on external commands | Medium | Small | P2 |
| 17 | ROB-4: Partial model download treated as cached | Low | Small | P2 |
| 18 | UX-6: Colors not disabled when piped | Low | Trivial | P3 |
| 19 | UX-2: No timing info | Low | Small | P3 |
| 20 | BUG-6: Dead code on redundant dry-run check | Low | Trivial | P3 |
| 21 | FEAT-5: ~/.local/bin not in PATH | Low | Small | P3 |
| 22 | ROB-6: Dry run needs python3 | Low | Trivial | P3 |
