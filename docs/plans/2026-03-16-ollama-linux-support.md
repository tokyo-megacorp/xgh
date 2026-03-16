# Ollama Linux Support

**Date:** 2026-03-16
**Status:** Implemented
**Scope:** Add Ollama as the inference backend for Linux/non-Apple-Silicon systems

---

## Background

xgh currently uses vllm-mlx as its local model server (OpenAI-compatible API on port 11434).
vllm-mlx is Apple Silicon-only. For Linux and Intel Mac, Ollama is the natural equivalent:
same port, same OpenAI-compatible API surface, similar model quality tier.

**Key architectural insight:** Cipher has **native Ollama support** (`embedding.type: ollama`,
`llm.provider: ollama` in cipher.yml). On Linux, use the native Ollama type instead of the
OpenAI-compat shim — this avoids the base64 encoding issue that required the
`fix-openai-embeddings.js` patch on macOS/vllm-mlx entirely.

Platform matrix:
| Platform | Backend | cipher.yml embedding.type |
|---|---|---|
| macOS Apple Silicon | vllm-mlx | `openai` (localhost OpenAI-compat) |
| Linux / Intel Mac | Ollama | `ollama` (native Cipher support) |

---

## Model Mapping Table

| Role | vllm-mlx (macOS HF ID) | Ollama model name | Dims | Notes |
|---|---|---|---|---|
| LLM default | mlx-community/Llama-3.2-3B-Instruct-4bit | llama3.2:3b | — | Confirmed in Ollama library |
| LLM tiny | mlx-community/Llama-3.2-1B-Instruct-4bit | llama3.2:1b | — | |
| LLM powerful | mlx-community/Mistral-7B-Instruct-v0.3-4bit | mistral:7b | — | |
| LLM balanced | mlx-community/Qwen3-4B-4bit | qwen3:4b | — | Confirmed (2.5GB, 256K ctx) |
| LLM strong | mlx-community/Qwen3-8B-4bit | qwen3:8b | — | Confirmed (5.2GB, 40K ctx) |
| **Embed default** | mlx-community/nomicai-modernbert-embed-base-8bit | **nomic-embed-text** | **768** | Cipher's recommended default; beats OpenAI ada-002; 8192 token ctx |
| Embed high-perf | _(no equivalent)_ | mxbai-embed-large | **1024** | ⚠️ Dim mismatch with 768 collections — must recreate |
| Embed fast | mlx-community/all-MiniLM-L6-v2-4bit | all-minilm:22m | **384** | ⚠️ Dim mismatch with 768 collections — must recreate |

**Embedding compatibility rule:** `nomic-embed-text` (768 dims) is the **only safe default** — it
matches existing Qdrant collections built on macOS. The post-hook dimension mismatch detector
handles cases where users switch to a different-dim model. The installer must warn explicitly
if the user selects a non-768 embed model and an existing 768-dim collection is detected.

---

## Implementation Steps

### Step 1 — Detect platform and set backend variable

- [x] In `install.sh`, after the OS detection preamble, add:
  ```bash
  # Determine inference backend
  if [[ "$(uname)" == "Darwin" ]] && [[ "$(uname -m)" == "arm64" ]]; then
    XGH_BACKEND="vllm-mlx"
  else
    XGH_BACKEND="ollama"
  fi
  ```
- [x] Export `XGH_BACKEND` and persist it in `~/.xgh/models.env` alongside `XGH_LLM_MODEL` / `XGH_EMBED_MODEL`.

---

### Step 2 — Install dependencies: branch on backend

In the dependencies lane of `install.sh`, the current block installs Homebrew, Node, Python, uv, vllm-mlx, and Qdrant. Wrap the vllm-mlx install block:

- [x] **macOS arm64 (vllm-mlx path):** keep existing logic unchanged.
- [x] **Linux/other (Ollama path):**
  - Check `command -v ollama`; if missing, run the official curl installer:
    ```bash
    curl -fsSL https://ollama.com/install.sh | sh
    ```
  - Add guard: if `ollama` still not found after install attempt, `warn` and `exit 1`.
  - Install Qdrant for Linux via binary download (no apt/snap available; binary is fully
    supported by Qdrant for local/dev use):
    ```bash
    ARCH=$(uname -m)  # x86_64 or aarch64
    QDRANT_VER=$(curl -sf https://api.github.com/repos/qdrant/qdrant/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    curl -fsSL "https://github.com/qdrant/qdrant/releases/download/${QDRANT_VER}/qdrant-${ARCH}-unknown-linux-gnu.tar.gz" \
      | tar -xz -C ~/.qdrant/bin/
    chmod +x ~/.qdrant/bin/qdrant
    ```
  - Write a systemd user service for Qdrant (Qdrant ships no unit file — write our own):
    ```ini
    [Unit]
    Description=Qdrant vector database
    After=network.target

    [Service]
    ExecStart=%h/.qdrant/bin/qdrant
    WorkingDirectory=%h/.qdrant/storage
    Restart=always
    RestartSec=5
    Environment=HOME=%h
    StandardOutput=append:%h/.xgh/logs/qdrant.log
    StandardError=append:%h/.xgh/logs/qdrant.log

    [Install]
    WantedBy=default.target
    ```
  - `loginctl enable-linger $USER` before enabling the service (required for user services
    to start without an active login session — SSH/server environments).

---

### Step 3 — Model selection UI: backend-aware pickers

In `install.sh`'s model selection lane, replace the single `LLM_MODELS` / `EMBED_MODELS` arrays with backend-conditional arrays:

- [x] Define `OLLAMA_LLM_MODELS` and `OLLAMA_EMBED_MODELS` parallel to the existing vllm-mlx arrays.
- [x] Select which array to use based on `$XGH_BACKEND`.
- [x] Change the custom-entry prompt label: macOS shows "HuggingFace model ID", Linux shows "Ollama model name (e.g. llama3.2:3b)".
- [x] The `_model_cached` helper currently checks the HuggingFace disk cache. Add a parallel `_ollama_model_pulled` helper:
  ```bash
  _ollama_model_pulled() { ollama list 2>/dev/null | grep -q "^${1}"; }
  ```
  Use it for pre-selecting defaults on Linux (marks already-pulled models as `(installed)`).

---

### Step 4 — Model download/pull: backend-aware

Replace the `huggingface_hub.snapshot_download` Python block:

- [x] **vllm-mlx path:** keep existing `uv run --with huggingface-hub python3 ...` block unchanged.
- [x] **Ollama path:** for each selected model, run:
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

- [x] Add `XGH_BACKEND=vllm-mlx` or `XGH_BACKEND=ollama` to this file.
- [x] Update the models.env generation block in `install.sh` to include `XGH_BACKEND`.

---

### Step 6 — cipher.yml: use native Ollama type on Linux

Cipher has first-class Ollama support (`type: ollama`, `provider: ollama`). On Linux, generate
cipher.yml using the native Ollama type rather than the OpenAI-compat shim:

- [x] Branch the cipher.yml template in install.sh on `$XGH_BACKEND`:
  - **vllm-mlx (macOS):** keep existing `embedding.type: openai` + `baseURL: http://localhost:11434/v1`
  - **ollama (Linux):**
    ```yaml
    llm:
      provider: ollama
      model: ${XGH_LLM_MODEL}       # e.g. llama3.2:3b
      baseURL: http://localhost:11434

    embedding:
      type: ollama
      model: ${XGH_EMBED_MODEL}     # e.g. nomic-embed-text
      baseURL: http://localhost:11434
      dimensions: 768
    ```
- [x] With `type: ollama`, Cipher does NOT go through the OpenAI SDK — the `fix-openai-embeddings.js` patch is **not needed on Linux**. No change to the wrapper, it's a no-op on Ollama.
- [x] The cipher.yml `sync` block added on 2026-03-16 must also branch on backend to write the correct type field.
- [x] No `OLLAMA_BASE_URL` env var needed in the MCP config — the native Ollama type reads from `baseURL` in cipher.yml directly.

---

### Step 7 — Port conflict detection (macOS)

On macOS, if Ollama is installed alongside vllm-mlx, they both try to use port 11434.

- [x] In the macOS dependency lane (before starting vllm-mlx), add:
  ```bash
  if command -v ollama &>/dev/null && pgrep -x ollama >/dev/null 2>&1; then
    warn "Ollama is running and will conflict with vllm-mlx on port 11434 — stopping Ollama"
    osascript -e 'quit app "Ollama"' 2>/dev/null || true
    pkill -f ollama 2>/dev/null || true
  fi
  ```
- [x] Post-install note on macOS: "Disable Ollama auto-start to prevent port 11434 conflicts with vllm-mlx."

---

### Step 8 — ingest-schedule.sh: Linux systemd services

`curl https://ollama.com/install.sh | sh` installs Ollama with its **own systemd system
service** (`ollama.service`) that auto-starts. xgh should not create a competing wrapper.

- [x] In `install_linux()`, after running the Ollama installer, just enable and verify:
  ```bash
  systemctl is-active ollama.service >/dev/null 2>&1 \
    || sudo systemctl enable --now ollama.service 2>/dev/null \
    || warn "Could not enable ollama.service — start manually: ollama serve"
  ```
- [x] Write a **separate** `~/.config/systemd/user/xgh-qdrant.service` for Qdrant (see Step 2 unit file).
- [x] `loginctl enable-linger $USER` before any `systemctl --user` calls.
- [x] `uninstall_linux()`: stop/disable `xgh-qdrant.service`; do NOT touch `ollama.service` (other apps may use it).

---

### Step 9 — com.xgh.models.plist: macOS-only, no functional change

- [x] Add comment: `<!-- macOS Apple Silicon only — for Linux/Intel see systemd/xgh-models.service -->`.

---

### Step 10 — techpack.yaml: add Ollama component

- [x] Add `ollama` component (Linux/non-arm64 path).
- [x] Annotate `vllm-mlx` component as Apple Silicon only.

---

### Step 11 — MCP env vars: branch on backend

The `_ENV_ARGS` passed to `claude mcp add -s user` are currently hardcoded to `openai` provider
and localhost URLs. Must be branched per backend.

- [ ] Replace the current flat `_ENV_ARGS` block with a backend-conditional one:

  **vllm-mlx** (keep existing — provider=openai, /v1 suffix):
  ```
  EMBEDDING_PROVIDER=openai   EMBEDDING_BASE_URL=http://localhost:11434/v1
  OPENAI_API_KEY=placeholder  OPENAI_BASE_URL=http://localhost:11434/v1
  LLM_PROVIDER=openai         LLM_BASE_URL=http://localhost:11434/v1
  ```

  **ollama** (new — provider=ollama, no /v1 suffix, no OPENAI_* keys):
  ```
  EMBEDDING_PROVIDER=ollama   EMBEDDING_BASE_URL=http://localhost:11434
  OLLAMA_BASE_URL=http://localhost:11434
  LLM_PROVIDER=ollama         LLM_BASE_URL=http://localhost:11434
  ```
  Omitting `OPENAI_API_KEY` / `OPENAI_BASE_URL` prevents the cipher-mcp wrapper from
  attempting OpenAI-compat paths when the native Ollama provider is active.

- [ ] Apply the same branching to the fallback `_CIPHER_ENV` JSON heredoc (written directly
  to `~/.claude.json` when `claude` CLI is unavailable).

### Step 11b — API compatibility: no code changes needed

Ollama's `/v1/embeddings` returns the same JSON shape as vllm-mlx. The existing `fix-openai-embeddings.js` patch in the cipher-mcp wrapper is a no-op on Ollama and safe to leave in place.

---

### Step 12 — start-models.sh: backend-aware

The generated `~/.xgh/start-models.sh` currently calls `exec vllm-mlx serve ...` unconditionally.

- [x] Branch on `$XGH_BACKEND` in the generation block:
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

## Resolved Decisions

| Question | Decision |
|---|---|
| Qwen3 on Ollama? | ✅ Confirmed available: `qwen3:4b` (2.5GB) and `qwen3:8b` (5.2GB) |
| Qdrant on Linux install method? | ✅ Binary download — no apt/snap exists; binary is fully supported by Qdrant for local use. arch-aware (`x86_64` / `aarch64`). |
| Ollama service management on Linux? | ✅ Rely on Ollama's own `ollama.service` (installed by `curl \| sh`). xgh only manages `xgh-qdrant.service` via systemd user. |
| Collection reset on dim mismatch? | ✅ Never auto-reset. The cipher-post-hook surfaces a diagnostic table and asks user to choose Option A (recreate, data loss) or Option B (switch model). `XGH_RESET_COLLECTION=1` available as escape hatch in installer. |
| Intel Mac? | ✅ Ollama path — `uname -m != arm64` → Ollama, regardless of OS. |
| cipher.yml type on Linux? | ✅ `type: ollama` (native Cipher support) — avoids the OpenAI SDK base64 encoding issue. macOS keeps `type: openai` (vllm-mlx compat). |
