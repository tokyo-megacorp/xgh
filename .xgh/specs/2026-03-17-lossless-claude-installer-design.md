# Design: xgh Installer — lossless-claude Integration

**Date:** 2026-03-17
**Status:** Draft
**Scope:** Replace Cipher with lossless-claude in xgh's installer; make context-mode required.

---

## Problem

xgh's `install.sh` owns the entire memory layer setup: vllm-mlx/Ollama/Qdrant infrastructure, model selection, cipher.yml generation, Cipher MCP registration, and Cipher-specific Pre/PostToolUse hooks. This logic belongs in lossless-claude, which is now the memory backend. xgh's installer should delegate to `lossless-claude install` rather than duplicating infrastructure setup.

---

## Goals

1. `lossless-claude install` is self-contained — runs the full memory stack setup (backends, models, Qdrant, cipher.yml, daemon service, Claude Code hooks + MCP).
2. xgh's installer reduces to: install binary → `lossless-claude install`.
3. context-mode is always installed (not optional).
4. No regressions: existing cipher.yml format and Qdrant setup are preserved exactly.

---

## Migration Strategy

Two-phase, safety-first:

**Phase 1 — Implement in lossless-claude, keep xgh unchanged**
Add the bash setup logic to lossless-claude. Test and confirm parity with the existing xgh behaviour. xgh still runs its old cipher code during this phase.

**Phase 2 — Switch xgh to delegate, remove old cipher code**
Only after Phase 1 is confirmed working: update xgh's installer to call `lossless-claude install`, and delete the cipher infrastructure blocks.

---

## Phase 1: lossless-claude Changes

### 1.1 Add `installer/setup.sh`

Near-verbatim copy of the following logic from xgh's `install.sh`:

- **Backend detection** — `XGH_BACKEND` picker (vllm-mlx on Apple Silicon, Ollama on Linux/Intel, remote if set)
- **Model selection** — interactive picker with installed-first sorting; reads existing `~/.cipher/cipher.yml` for current models; respects `XGH_LLM_MODEL` / `XGH_EMBED_MODEL` env overrides
- **vllm-mlx path** — installs `uv`, `vllm-mlx`; kills conflicting Ollama; installs Qdrant via Homebrew; writes + loads launchd plist; pulls HuggingFace models
- **Ollama path** — installs Ollama; installs Qdrant binary (arch-aware); writes systemd user service; pulls Ollama models
- **Remote path** — no local model server; installs Qdrant for vector storage
- **cipher.yml generation** — writes `~/.cipher/cipher.yml` with selected models and backend URLs (format unchanged)

The script accepts the same env vars as xgh for non-interactive use:
`XGH_BACKEND`, `XGH_LLM_MODEL`, `XGH_EMBED_MODEL`, `XGH_REMOTE_URL`, `XGH_DRY_RUN`, `XGH_PRESET`.

`XGH_DRY_RUN=1` is fully respected — when set, `setup.sh` skips all installs and service writes, same as in xgh's installer.

**`XGH_PRESET` and `PACK_DIR` coupling:** xgh uses `PACK_DIR` (the xgh pack path) to resolve preset YAML files for default model selection. `setup.sh` cannot rely on `PACK_DIR` existing. Instead, `setup.sh` bundles its own copy of the preset defaults inline (same values as the xgh pack's presets) and falls back to them when `XGH_PRESET` is set but no external preset file is found. When called from xgh's installer, `XGH_LLM_MODEL` and `XGH_EMBED_MODEL` are already resolved before `lossless-claude install` is called, so `setup.sh` skips the picker and uses the provided values directly.

### 1.2 `lossless-claude install` invokes `setup.sh`

In `installer/install.ts`, before the existing steps, add:

```typescript
// Step 0: run infrastructure setup
const setupScript = join(dirname(fileURLToPath(import.meta.url)), "setup.sh");
const result = spawnSync("bash", [setupScript], { stdio: "inherit", env: process.env });
if (result.status !== 0) {
  console.warn(`Warning: setup.sh exited with code ${result.status} — continuing anyway`);
}
```

`setup.sh` failures are **non-fatal** (warn and continue), consistent with xgh's own `|| warn "..."` pattern. Individual steps inside `setup.sh` already warn on failure without aborting. A non-zero exit from `setup.sh` means at least one optional step failed (e.g. a model pull timed out); the TypeScript steps (config, hooks, daemon) still run so Claude Code integration is registered.

This means the full install sequence becomes:
1. `setup.sh` — backend, models, Qdrant, cipher.yml (bash, interactive)
2. Create `~/.lossless-claude/` and `config.json` (TypeScript)
3. Merge hooks + MCP into `~/.claude/settings.json` (TypeScript)
4. Set up daemon service — launchd/systemd (TypeScript, already implemented)
5. Start daemon

**Soften the cipher guard:** `install.ts` currently hard-exits if `~/.cipher/cipher.yml` is missing (`process.exit(1)`). Since `setup.sh` is now responsible for creating it, this guard must be changed to a warn + continue:
```typescript
if (!existsSync(cipherConfig)) {
  console.warn("Warning: ~/.cipher/cipher.yml not found — semantic search will be unavailable until setup completes");
}
```

### 1.3 Packaging `setup.sh` (Option A — copy to dist)

TypeScript compilation does not copy `.sh` files. The `files` array in `package.json` only includes `dist/`. Fix:

1. Update the `build` script in `package.json`:
   ```
   "build": "tsc && cp installer/setup.sh dist/installer/setup.sh"
   ```
2. No change to `files` needed — `dist/` already covers `dist/installer/`.

After compilation `dist/installer/setup.sh` exists alongside `dist/installer/install.js`, so the `import.meta.url`-relative path in §1.2 resolves correctly.

### 1.4 Files in `lossless-claude`

```
installer/
  setup.sh        ← new: verbatim copy of cipher infrastructure bash from xgh
  install.ts      ← updated: invoke setup.sh, soften cipher guard
  uninstall.ts    ← unchanged
package.json      ← updated: build script copies setup.sh to dist/
```

---

## Phase 2: xgh `install.sh` Changes

Applied only after Phase 1 is confirmed working.

### 2.1 Replace §3b "Cipher Infrastructure" with lossless-claude install

**Remove:**
- `npm install -g @byterover/cipher`
- cipher-mcp wrapper (`~/.local/bin/cipher-mcp`)
- `fix-openai-embeddings.js` (`~/.local/lib/fix-openai-embeddings.js`)
- `qdrant-store.js` (`~/.local/lib/qdrant-store.js`)
- All model selection / cipher.yml generation logic (moved to lossless-claude)

**Replace with:**
```bash
# ── 3b. lossless-claude ────────────────────────────────
lane "Wiring up the memory layer 🧬"

if ! command -v lossless-claude &>/dev/null; then
  info "Installing lossless-claude..."
  npm install -g github:extreme-go-horse/lossless-claude || {
    warn "Could not install lossless-claude — install manually: npm install -g github:extreme-go-horse/lossless-claude"
  }
else
  info "lossless-claude already installed: $(command -v lossless-claude)"
fi

lossless-claude install || warn "lossless-claude install failed — run manually: lossless-claude install"
```

All env vars (`XGH_BACKEND`, `XGH_LLM_MODEL`, etc.) are already in the environment, so `lossless-claude install` picks them up via `setup.sh`.

### 2.2 Remove §4 "Cipher MCP Server"

Delete the entire block. `lossless-claude install` already handles MCP registration in `~/.claude/settings.json`.

**Legacy `.mcp.json` cleanup** — retained in xgh's installer (not moved to lossless-claude). xgh knows `$PWD` (the project being installed into); lossless-claude does not. The block that removes stale `cipher` entries from project-level `.mcp.json` stays in xgh's Phase 2 installer, updated to also remove any stale `cipher` entry from `~/.claude/mcp.json` if present.

### 2.3 Remove §5/6 Cipher Pre/PostToolUse hooks

Delete the cipher Pre/PostToolUse hook blocks. These were workarounds for Cipher-specific failure modes (dimension mismatch, `extracted:0`) that do not exist in lossless-claude.

The `SETTINGS_FILE` and hook infrastructure remain — xgh's own hooks (context-mode PreToolUse guidance) are still written in §6.

### 2.4 Remove store-memory skill

Delete the `store-memory` skill installation block. It was a Cipher extraction bypass; lossless-claude's `lcm_store` is the direct replacement and needs no workaround skill.

### 2.5 Make context-mode required

**Remove** context-mode from the `XGH_INSTALL_PLUGINS` optional block.

**Add** unconditional install in §1 dependencies, after Node.js check:
```bash
# context-mode (required — session optimizer, 98% context savings)
if command -v claude &>/dev/null; then
  info "Installing context-mode..."
  claude plugin marketplace add "mksglu/context-mode" &>/dev/null || true
  claude plugin install "context-mode@context-mode" &>/dev/null || \
    warn "Could not install context-mode — install manually: claude plugin install context-mode@context-mode"
fi
```

**Update** the optional plugins lane: remove context-mode entry, rename lane from "Optional superpowers 🦸" to "Superpowers 🦸" (only superpowers remains optional).

---

## What Stays Unchanged

- vllm-mlx, Ollama, Qdrant install logic (moved, not modified)
- cipher.yml format (lossless-claude reads the same file, same keys)
- Plugin registration (§7), context tree (§8), CLAUDE.local.md (§10)
- `XGH_DRY_RUN` support: `setup.sh` respects `XGH_DRY_RUN=1`

---

## Success Criteria

1. `lossless-claude install` run on a clean machine produces identical cipher.yml, Qdrant service, and model configuration as the current xgh installer
2. `lossless-claude install` registers MCP + hooks in `~/.claude/settings.json` and starts the persistent daemon
3. After Phase 2: `bash install.sh` on a clean machine produces the same end state as before, with no cipher binary or cipher-mcp wrapper installed
4. context-mode is installed on every `bash install.sh` run without prompting
5. `XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh` completes without error
