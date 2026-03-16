# Ollama Linux Support

**Date:** 2026-03-16
**Status:** Planning
**Scope:** Add Ollama as the inference backend for Linux/non-Apple-Silicon systems

---

## Background

xgh currently uses vllm-mlx as its local model server (OpenAI-compatible API on port 11434).
vllm-mlx is Apple Silicon-only. For Linux (and Intel Mac), Ollama is the natural equivalent:
same port, same OpenAI-compatible API surface, similar model quality tier.

The key architectural constraint: `~/.cipher/cipher.yml`, `lib/workspace-write.js`, and all
skills must remain identical across platforms. Only the install/start mechanism and the model
name strings written into `models.env` differ.

---

## Model Mapping Table

| Role | vllm-mlx (macOS HF ID) | Ollama model name | Dims | Notes |
|---|---|---|---|---|
| LLM default | mlx-community/Llama-3.2-3B-Instruct-4bit | llama3.2:3b | — | Same base model |
| LLM tiny | mlx-community/Llama-3.2-1B-Instruct-4bit | llama3.2:1b | — | |
| LLM powerful | mlx-community/Mistral-7B-Instruct-v0.3-4bit | mistral:7b | — | |
| LLM balanced | mlx-community/Qwen3-4B-4bit | qwen3:4b | — | Check Ollama library availability |
| LLM strong | mlx-community/Qwen3-8B-4bit | qwen3:8b | — | Check Ollama library availability |
| Embed default | mlx-community/nomicai-modernbert-embed-base-8bit | nomic-embed-text | 768 | CRITICAL: same dims |
| Embed smaller | mlx-community/nomicai-modernbert-embed-base-4bit | nomic-embed-text | 768 | No direct 4-bit Ollama equivalent; use same model |
| Embed fast | mlx-community/all-MiniLM-L6-v2-4bit | all-minilm:22m | 384 | Dims mismatch if switching from 768 — warn user |

**Embedding compatibility rule:** Never mix a 768-dim Qdrant collection with a 384-dim model.
The installer must warn if the existing collection was created with a different embedding model.

---

## Implementation Steps

### Step 1 — Detect platform and set backend variable

- [ ] In `install.sh`, after the OS detection preamble, add:
  ```bash
  # Determine inference backend
  if [[ "$(uname)" == "Darwin" ]] && [[ "$(uname -m)" == "arm64" ]]; then
    XGH_BACKEND="vllm-mlx"
  else
    XGH_BACKEND="ollama"
  fi
  ```
- [ ] Export `XGH_BACKEND` and persist it in `~/.xgh/models.env` alongside `XGH_LLM_MODEL` / `XGH_EMBED_MODEL`.

---

### Step 2 — Install dependencies: branch on backend

In the dependencies lane of `install.sh`, the current block installs Homebrew, Node, Python, uv, vllm-mlx, and Qdrant. Wrap the vllm-mlx install block:

- [ ] **macOS arm64 (vllm-mlx path):** keep existing logic unchanged.
- [ ] **Linux/other (Ollama path):**
  - Check `command -v ollama`; if missing, run the official curl installer:
    ```bash
    curl -fsSL https://ollama.com/install.sh | sh
    ```
  - Add guard: if `ollama` still not found after install attempt, `warn` and `exit 1`.
  - Install Qdrant for Linux: download the latest binary from GitHub releases to `~/.qdrant/bin/qdrant` (no Homebrew on Linux). Use:
    ```bash
    QDRANT_VER=$(curl -sf https://api.github.com/repos/qdrant/qdrant/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    curl -fsSL "https://github.com/qdrant/qdrant/releases/download/${QDRANT_VER}/qdrant-x86_64-unknown-linux-gnu.tar.gz" | tar -xz -C ~/.qdrant/bin/
    ```
  - Start Qdrant as background process on Linux (no launchd/systemd for Qdrant — just nohup).

---

### Step 3 — Model selection UI: backend-aware pickers

In `install.sh`'s model selection lane, replace the single `LLM_MODELS` / `EMBED_MODELS` arrays with backend-conditional arrays:

- [ ] Define `OLLAMA_LLM_MODELS` and `OLLAMA_EMBED_MODELS` parallel to the existing vllm-mlx arrays.
- [ ] Select which array to use based on `$XGH_BACKEND`.
- [ ] Change the custom-entry prompt label: macOS shows "HuggingFace model ID", Linux shows "Ollama model name (e.g. llama3.2:3b)".
- [ ] The `_model_cached` helper currently checks the HuggingFace disk cache. Add a parallel `_ollama_model_pulled` helper:
  ```bash
  _ollama_model_pulled() { ollama list 2>/dev/null | grep -q "^${1}"; }
  ```
  Use it for pre-selecting defaults on Linux (marks already-pulled models as `(installed)`).

---

### Step 4 — Model download/pull: backend-aware

Replace the `huggingface_hub.snapshot_download` Python block:

- [ ] **vllm-mlx path:** keep existing `uv run --with huggingface-hub python3 ...` block unchanged.
- [ ] **Ollama path:** for each selected model, run:
  ```bash
  ollama pull "${model}"
  ```
  Run sequentially; show progress. If pull fails, warn but do not abort.

---

### Step 5 — models.env: store backend

The `~/.xgh/models.env` file (sourced by `ingest-schedule.sh` and `start-models.sh`) currently stores:

```bash
XGH_LLM_MODEL=...
XGH_EMBED_MODEL=...
XGH_MODEL_PORT=11434
```

- [ ] Add `XGH_BACKEND=vllm-mlx` or `XGH_BACKEND=ollama` to this file.
- [ ] Update the models.env generation block in `install.sh` to include `XGH_BACKEND`.

---

### Step 6 — cipher.yml: correct model names (no change to logic)

The `install.sh` Cipher section writes `~/.cipher/cipher.yml` using `$XGH_LLM_MODEL` / `$XGH_EMBED_MODEL` verbatim. Since Steps 3–4 already set these to platform-appropriate values (HF IDs on macOS, Ollama names on Linux), no change is needed here.

- [ ] Verify the `baseUrl` remains `http://localhost:11434/v1` — identical for both backends.
- [ ] The existing `sync` block (added 2026-03-16) correctly updates model names on reinstall.

---

### Step 7 — Port conflict detection (macOS)

On macOS, if Ollama is installed alongside vllm-mlx, they both try to use port 11434.

- [ ] In the macOS dependency lane (before starting vllm-mlx), add:
  ```bash
  if command -v ollama &>/dev/null && pgrep -x ollama >/dev/null 2>&1; then
    warn "Ollama is running and will conflict with vllm-mlx on port 11434 — stopping Ollama"
    osascript -e 'quit app "Ollama"' 2>/dev/null || true
    pkill -f ollama 2>/dev/null || true
  fi
  ```
- [ ] Post-install note on macOS: "Disable Ollama auto-start to prevent port 11434 conflicts with vllm-mlx."

---

### Step 8 — ingest-schedule.sh: Linux systemd service branches on backend

The existing `install_linux()` hardcodes `vllm-mlx` in the systemd unit:

- [ ] Source `~/.xgh/models.env` at the top (already done via `MODELS_ENV` variable).
- [ ] Branch the systemd `ExecStart` on `$XGH_BACKEND`:
  - **vllm-mlx:** `ExecStart=${VLLM_BIN} serve ${XGH_LLM_MODEL} --embedding-model ${XGH_EMBED_MODEL} --port ${XGH_MODEL_PORT} --host 127.0.0.1`
  - **ollama:** `ExecStart=/usr/local/bin/ollama serve` with `Environment=OLLAMA_HOST=127.0.0.1:11434`
- [ ] Add `loginctl enable-linger $USER` before `systemctl --user daemon-reload` (required for user services to start without an active login session).
- [ ] `uninstall_linux()` for Ollama: only stop `xgh-models.service`, do not uninstall Ollama itself (other apps may use it).

---

### Step 9 — com.xgh.models.plist: macOS-only, no functional change

- [ ] Add comment: `<!-- macOS Apple Silicon only — for Linux/Intel see systemd/xgh-models.service -->`.

---

### Step 10 — techpack.yaml: add Ollama component

- [ ] Add `ollama` component (Linux/non-arm64 path).
- [ ] Annotate `vllm-mlx` component as Apple Silicon only.

---

### Step 11 — API compatibility: no changes needed

Ollama's `/v1/embeddings` returns the same JSON shape as vllm-mlx. The existing `fix-openai-embeddings.js` patch in the cipher-mcp wrapper is a no-op on Ollama and safe to leave in place.

---

### Step 12 — start-models.sh: backend-aware

The generated `~/.xgh/start-models.sh` currently calls `exec vllm-mlx serve ...` unconditionally.

- [ ] Branch on `$XGH_BACKEND` in the generation block:
  - **vllm-mlx:** keep existing command.
  - **ollama:**
    ```bash
    echo "Ensuring Ollama models are pulled..."
    ollama pull "${XGH_LLM_MODEL}"
    ollama pull "${XGH_EMBED_MODEL}"
    exec ollama serve
    ```

---

## Risk and Gotcha List

| Risk | Severity | Mitigation |
|---|---|---|
| Ollama `nomic-embed-text` is 768-dim (same as ModernBERT) | Low | Compatible — no collection rebuild needed |
| `all-minilm` is 384-dim — mixing with 768-dim collection breaks Qdrant upserts | High | Warn at install time if switching embed dims; offer `XGH_RESET_COLLECTION=1` |
| Ollama `/v1/embeddings` in older versions may not accept `encoding_format` param | Medium | HTTP patch in cipher-mcp wrapper handles gracefully; require `ollama >= 0.1.47` |
| Qwen3 models may not be in Ollama library | Medium | Pre-check with `ollama show qwen3:4b`; fall back to `llama3.2:3b` with warning |
| Port 11434 already taken by system Ollama on Linux | Medium | Check `lsof -i :11434` before starting; if already Ollama, skip service install |
| `systemctl --user` requires lingering (no SSH without `loginctl enable-linger`) | Medium | Add `loginctl enable-linger $USER` to `install_linux()` |
| `ollama serve` binds to `0.0.0.0` by default (security) | Low | Set `OLLAMA_HOST=127.0.0.1:11434` in systemd unit |
| macOS Intel — neither vllm-mlx nor Ollama is ideal | Low | Treat as Linux path (`uname -m != arm64` → Ollama) |

---

## Open Questions

1. **Qwen3 on Ollama:** Available? If not, replace with `gemma3:4b` / `gemma3:9b` as Linux LLM options?
2. **Qdrant on Linux:** Direct binary download vs `apt`/`snap` vs Docker? Binary avoids root requirement.
3. **Ollama service management on Linux:** Wrap `ollama serve` in `xgh-models.service`, or rely on Ollama's own systemd service installed by `curl | sh`?
4. **Collection reset UX:** Auto-delete on dim mismatch (data loss) or require `XGH_RESET_COLLECTION=1`?
5. **Intel Mac:** Ollama backend or separate warning about poor performance?
