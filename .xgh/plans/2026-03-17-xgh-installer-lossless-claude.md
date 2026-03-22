# xgh: Installer — Switch to lossless-claude & Make context-mode Required

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Cipher infrastructure in xgh's `install.sh` with `lossless-claude install`, and make context-mode a required dependency.

**Architecture:** xgh's installer installs the `lossless-claude` binary from GitHub then delegates the entire memory stack setup to `lossless-claude install`. Cipher npm, wrapper scripts, MCP registration, and Pre/PostToolUse hooks are removed. context-mode moves from optional prompt to unconditional install.

**Tech Stack:** Bash, `install.sh` (xgh installer). No new files — all changes are in `install.sh`.

**Prerequisite:** Plan `2026-03-17-installer-setup-sh.md` in lossless-claude must be complete and confirmed working before executing this plan.

---

## File Map

| File | Change |
|---|---|
| `install.sh` | **Modify** — 5 targeted removals + 2 additions |

---

## Task 1: Make context-mode a required dependency

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add unconditional context-mode install to §1 dependencies**

In `install.sh`, find the Node.js install block in `§1. Dependencies` (around line 110):
```bash
# Node.js and npm (required by Cipher MCP wrapper and helper scripts)
if ! command -v node &>/dev/null; then
```

After the Node.js block (after its `fi`), add:
```bash
# context-mode (required — session optimizer, 98% context savings)
if command -v claude &>/dev/null; then
  info "Installing context-mode..."
  claude plugin marketplace add "mksglu/context-mode" &>/dev/null || true
  claude plugin install "context-mode@context-mode" &>/dev/null || \
    warn "Could not install context-mode — install manually: claude plugin install context-mode@context-mode"
else
  warn "Claude CLI not found — install context-mode manually: claude plugin install context-mode@context-mode"
fi
```

- [ ] **Step 2: Remove context-mode from the optional plugins block**

In `install.sh`, find the optional plugins section (around line 1881):
```bash
# ── context-mode ────────────────────────────────────────
INSTALL_CONTEXT_MODE="n"
if [ "$XGH_INSTALL_PLUGINS" = "all" ]; then
  INSTALL_CONTEXT_MODE="y"
elif [ "$XGH_INSTALL_PLUGINS" = "ask" ]; then
  echo -e "  ${BOLD}context-mode${NC} ${DIM}by mksglu${NC}"
  echo -e "  ${DIM}Session optimizer — 98% context savings, sandboxed execution, FTS5 search${NC}"
  echo ""
  read -r -p "  🤖 Install? [y/N] " INSTALL_CONTEXT_MODE
fi
if [[ "$(printf '%s' "$INSTALL_CONTEXT_MODE" | tr '[:upper:]' '[:lower:]')" =~ ^y ]]; then
  install_plugin "mksglu/context-mode" "context-mode@context-mode" "context-mode"
fi
```

Delete this entire block.

- [ ] **Step 3: Rename the optional plugins lane**

Find:
```bash
lane "Optional superpowers 🦸"
```
Change to:
```bash
lane "Superpowers 🦸"
```

- [ ] **Step 4: Dry-run test**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh
```
Expected: runs without error; context-mode step appears in §1, not in optional section.

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat: make context-mode a required dependency in installer"
```

---

## Task 2: Replace §3b cipher infrastructure with lossless-claude install

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Replace the cipher infrastructure block**

Find the entire `§3b. Cipher Infrastructure` block (approximately lines 584–1028 in the current file). It starts with:
```bash
# ── 3b. Cipher Infrastructure ──────────────────────────
lane "Wiring up the memory layer 🧬"
```
And ends after the cipher.yml sync python3 block.

Replace the entire block with:
```bash
# ── 3b. lossless-claude ────────────────────────────────
lane "Wiring up the memory layer 🧬"

if [ "$XGH_DRY_RUN" -eq 0 ]; then
  if ! command -v lossless-claude &>/dev/null; then
    if command -v npm &>/dev/null; then
      info "Installing lossless-claude..."
      npm install -g github:extreme-go-horse/lossless-claude &>/dev/null || {
        warn "Could not install lossless-claude — install manually: npm install -g github:extreme-go-horse/lossless-claude"
      }
    else
      warn "npm not found — install Node.js first, then: npm install -g github:extreme-go-horse/lossless-claude"
    fi
  else
    info "lossless-claude already installed: $(command -v lossless-claude)"
  fi

  lossless-claude install || warn "lossless-claude install failed — run manually: lossless-claude install"
fi
```

All env vars (`XGH_BACKEND`, `XGH_LLM_MODEL`, `XGH_EMBED_MODEL`, `XGH_REMOTE_URL`, `XGH_PRESET`, `XGH_DRY_RUN`) are already in the environment when `lossless-claude install` is called — `setup.sh` inside lossless-claude picks them up automatically via `process.env`.

Note: §0 (backend picker) and §1 (vllm-mlx/Ollama/Qdrant dependencies) and §2 (model selection) were previously needed to feed into §3b. After this change, those sections are also redundant (lossless-claude's `setup.sh` does all of it). **Do not remove §0/§1/§2 in this task** — remove them in Task 6 after confirming end-to-end.

- [ ] **Step 2: Dry-run test**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh
```
Expected: runs without error; "Wiring up the memory layer" lane appears; no cipher references in output.

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: replace cipher infrastructure with lossless-claude install in installer"
```

---

## Task 3: Remove §4 cipher MCP section, update legacy .mcp.json cleanup

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Replace §4 cipher MCP with legacy cleanup only**

Find the `§4. Cipher MCP Server` block. It contains:
1. `lane "Configuring Cipher MCP 🔮"`
2. `CLAUDE_DIR` setup
3. Legacy `.mcp.json` cleanup block (removes stale cipher entries)
4. cipher MCP registration into global settings

**Keep** only the legacy `.mcp.json` cleanup (step 3 above). **Remove** the lane header, MCP registration, and cipher-specific env var logic.

The remaining block should look like:
```bash
# ── 4. Legacy MCP cleanup ──────────────────────────────
CLAUDE_DIR="${PWD}/.claude"
mkdir -p "${CLAUDE_DIR}"

# Clean up any legacy project-level cipher entries from .mcp.json
if [ -f "${PWD}/.mcp.json" ]; then
  LEGACY_KEYS=$(jq -r '.mcpServers | keys[]' "${PWD}/.mcp.json" 2>/dev/null || echo "")
  if [ "$LEGACY_KEYS" = "cipher" ]; then
    rm -f "${PWD}/.mcp.json"
    info "Removed legacy .mcp.json (cipher entry)"
  elif echo "$LEGACY_KEYS" | grep -q "cipher"; then
    jq 'del(.mcpServers.cipher)' "${PWD}/.mcp.json" > "${PWD}/.mcp.json.tmp" \
      && mv "${PWD}/.mcp.json.tmp" "${PWD}/.mcp.json"
    info "Removed stale cipher entry from project .mcp.json"
  fi
fi

# Clean up any stale cipher entry from global ~/.claude/mcp.json
GLOBAL_MCP="${HOME}/.claude/mcp.json"
if [ -f "$GLOBAL_MCP" ] && jq -e '.mcpServers.cipher' "$GLOBAL_MCP" &>/dev/null; then
  jq 'del(.mcpServers.cipher)' "$GLOBAL_MCP" > "${GLOBAL_MCP}.tmp" \
    && mv "${GLOBAL_MCP}.tmp" "$GLOBAL_MCP"
  info "Removed stale cipher entry from ~/.claude/mcp.json"
fi
```

- [ ] **Step 2: Dry-run test**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh
```
Expected: no errors; no "Configuring Cipher MCP" lane.

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "refactor: remove cipher MCP registration, keep legacy mcp.json cleanup"
```

---

## Task 4: Remove cipher Pre/PostToolUse hooks

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Remove cipher hook blocks**

In `install.sh` §5/6, find and delete these two blocks entirely:

**Block 1** — PreToolUse hook (starts with):
```bash
# -- Cipher Pre/PostToolUse hooks (detect extraction failures, suggest direct storage) --
```
Delete from that comment through the closing of the PreToolUse hook heredoc.

**Block 2** — PostToolUse hook (the dimension mismatch / extracted:0 detection). Delete from the PostToolUse hook comment through its closing heredoc.

Also delete the two `Add cipher Pre/PostToolUse hooks to settings` blocks in §6 that register these hooks into `settings.json`.

The `SETTINGS_FILE`, `HOOKS_DIR`, and xgh's own existing hooks remain untouched.

- [ ] **Step 2: Dry-run test**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh
```
Expected: no errors; no cipher hook references.

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "refactor: remove cipher Pre/PostToolUse hooks from installer"
```

---

## Task 5: Remove store-memory skill

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Delete store-memory skill block**

Find:
```bash
# -- store-memory skill (global, for direct Qdrant storage bypassing cipher extraction) --
info "Setting up store-memory skill"
STORE_MEMORY_DIR="${HOME}/.claude/skills/store-memory"
```

Delete from that comment through the closing `fi` of the store-memory block.

- [ ] **Step 2: Dry-run test**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh
```
Expected: no errors; no store-memory references.

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "refactor: remove store-memory skill (cipher workaround, no longer needed)"
```

---

## Task 6: Remove now-redundant §0/§1/§2 sections

**Files:**
- Modify: `install.sh`

**Gate:** Only do this task after running a real (non-dry-run) install with lossless-claude and confirming that `setup.sh` correctly handles backend detection, model selection, vllm-mlx/Ollama/Qdrant setup, and cipher.yml generation.

- [ ] **Step 1: Remove §0 backend picker**

Delete the entire `§0. Backend / remote URL picker` block.

- [ ] **Step 2: Remove §1 backend-specific dependencies**

In `§1. Dependencies`, delete the backend-specific blocks:
- vllm-mlx: `uv`, `vllm-mlx`, Qdrant via Homebrew + launchd
- Ollama: Ollama install, Qdrant binary + systemd
- Remote: Qdrant local install

Keep: Node.js and Python3 checks (still needed by xgh for other purposes).

- [ ] **Step 3: Remove §2 model selection**

Delete the entire `§2. Model Selection` block.

- [ ] **Step 4: Dry-run test**

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh
```
Expected: no errors.

- [ ] **Step 5: Full test suite**

```bash
bash tests/test-install.sh
bash tests/test-config.sh
bash tests/test-techpack.sh
bash tests/test-uninstall.sh
```
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add install.sh
git commit -m "refactor: remove §0/§1/§2 from install.sh (moved to lossless-claude setup.sh)"
```
