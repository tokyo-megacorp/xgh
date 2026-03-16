# Remote Backend Support

**Date:** 2026-03-16
**Status:** Ready to implement (after Ollama Linux plan)
**Scope:** Add a `remote` backend that points xgh at an external inference server over the network

---

## Motivation

Concrete use case: Mac Mini runs vllm-mlx (LLM + embeddings on port 11434). A Raspberry Pi
on the same network wants to install xgh and use the Mac Mini's inference server — no local
model server needed on the Pi, just Qdrant + Cipher MCP pointing at `http://macmini.local:11434`.

---

## Backend Matrix (updated)

| Platform | Backend | Model server | cipher.yml type |
|---|---|---|---|
| macOS Apple Silicon | `vllm-mlx` | local vllm-mlx | `openai` (localhost) |
| Linux / Intel Mac | `ollama` | local Ollama | `ollama` (localhost) |
| Any — remote server | `remote` | **none** (external) | `openai` (remote URL) |

The `remote` backend is platform-agnostic — it can be selected on any OS.

---

## What changes

### Server side (Mac Mini / the machine running vllm-mlx)

vllm-mlx currently binds to `127.0.0.1` (see `com.xgh.models.plist`). To accept remote
connections, it must bind to `0.0.0.0` or a specific interface.

- [ ] Add `--serve-network` flag to `install.sh` (or auto-detect if not on loopback):
  When `XGH_BACKEND=vllm-mlx` and `XGH_SERVE_NETWORK=1`, update the plist to use
  `--host 0.0.0.0` instead of `--host 127.0.0.1`.
- [ ] Update `com.xgh.models.plist` template: replace hardcoded `127.0.0.1` with
  `XGH_MODEL_HOST` placeholder (default `127.0.0.1`, overridable).
- [ ] Post-install note when `XGH_SERVE_NETWORK=1`:
  ```
  ✓ vllm-mlx bound to 0.0.0.0:11434 — accessible from other devices on your network.
  Firewall: ensure port 11434 is allowed inbound.
  ```

### Client side (Raspberry Pi / the machine consuming the remote server)

- [ ] `XGH_BACKEND=remote` skips ALL model server install steps (no vllm-mlx, no Ollama,
  no Qdrant via brew/binary — but Qdrant still runs locally for vector storage).
- [ ] Prompt for remote server URL:
  ```
  Remote inference server URL [http://192.168.1.x:11434]:
  ```
  Stored as `XGH_REMOTE_URL`. Validate: must start with `http://` or `https://`.
- [ ] Auto-detect available models by querying `GET ${XGH_REMOTE_URL}/v1/models`:
  ```bash
  _fetch_remote_models() {
    curl -sf "${XGH_REMOTE_URL}/v1/models" 2>/dev/null \
      | python3 -c "import json,sys; [print(m['id']) for m in json.load(sys.stdin).get('data',[])]"
  }
  ```
  If the server is reachable and returns models, present them as a picker (same UI as
  vllm-mlx/Ollama pickers). If unreachable, warn but allow manual entry.
- [ ] `cipher.yml` for remote backend:
  ```yaml
  llm:
    provider: openai
    model: ${XGH_LLM_MODEL}
    maxIterations: 50
    apiKey: placeholder
    baseURL: ${XGH_REMOTE_URL}/v1

  embedding:
    type: openai
    model: ${XGH_EMBED_MODEL}
    apiKey: placeholder
    baseURL: ${XGH_REMOTE_URL}/v1
    dimensions: 768
  ```
  Uses `type: openai` (OpenAI-compat) — works for both vllm-mlx and Ollama remote servers.
- [ ] MCP env vars for remote: `EMBEDDING_BASE_URL` and `LLM_BASE_URL` set to
  `${XGH_REMOTE_URL}/v1` instead of localhost.
- [ ] Qdrant still runs **locally** on the client machine (Pi). Install Qdrant binary same
  as Ollama Linux path (Steps 2/8 of the Ollama plan). The Pi has its own vector store.
- [ ] `models.env` stores `XGH_BACKEND=remote` and `XGH_REMOTE_URL=http://...`.
- [ ] `start-models.sh` for remote backend:
  ```bash
  #!/usr/bin/env bash
  # xgh model server — remote backend
  # No local model server needed. Verifying remote server connectivity...
  if curl -sf "${XGH_REMOTE_URL}/v1/models" >/dev/null 2>&1; then
    echo "✓ Remote inference server reachable: ${XGH_REMOTE_URL}"
  else
    echo "✗ Cannot reach remote inference server: ${XGH_REMOTE_URL}"
    echo "  Check network connectivity and that the server is running."
    exit 1
  fi
  ```

---

## Implementation Steps

### Step 1 — Backend detection: allow `remote` override

- [x] In install.sh platform detection block, allow explicit override:
  ```bash
  if [ -n "$XGH_BACKEND" ] && [ "$XGH_BACKEND" = "remote" ]; then
    : # keep as remote — user explicitly set this
  elif [[ "$(uname)" == "Darwin" ]] && [[ "$(uname -m)" == "arm64" ]]; then
    XGH_BACKEND="${XGH_BACKEND:-vllm-mlx}"
  else
    XGH_BACKEND="${XGH_BACKEND:-ollama}"
  fi
  ```
- [x] In interactive install (non-dry-run, no XGH_BACKEND set), add a backend picker:
  ```
  Which inference backend?

    1) Local — vllm-mlx (macOS Apple Silicon)     [auto-detected]
    2) Local — Ollama (Linux / Intel Mac)
    3) Remote — connect to another machine's server
  ```
  If the user picks 3, prompt for `XGH_REMOTE_URL`.

### Step 2 — Remote URL prompt and validation

- [x] After backend picker, if `XGH_BACKEND=remote`:
  ```bash
  if [ -z "$XGH_REMOTE_URL" ]; then
    read -r -p "  🐴 Remote server URL [http://192.168.1.x:11434]: " XGH_REMOTE_URL
    XGH_REMOTE_URL="${XGH_REMOTE_URL:-}"
    # validate
    if [[ ! "$XGH_REMOTE_URL" =~ ^https?:// ]]; then
      error "URL must start with http:// or https://"
      exit 1
    fi
  fi
  ```
- [x] Test connectivity before proceeding:
  ```bash
  if curl -sf --max-time 5 "${XGH_REMOTE_URL}/v1/models" >/dev/null 2>&1; then
    info "Remote server reachable ✓"
  else
    warn "Cannot reach ${XGH_REMOTE_URL} — continuing anyway (server may not be running yet)"
  fi
  ```

### Step 3 — Model picker: query remote server

- [x] `_model_available` for remote backend:
  ```bash
  _model_available() {
    curl -sf "${XGH_REMOTE_URL}/v1/models" 2>/dev/null \
      | python3 -c "
import json,sys
data=json.load(sys.stdin)
ids=[m['id'] for m in data.get('data',[])]
print('yes' if '${1}' in ids else 'no')
" 2>/dev/null | grep -q "^yes"
  }
  ```
- [x] Auto-populate model lists from remote `/v1/models` if reachable:
  ```bash
  if curl -sf --max-time 5 "${XGH_REMOTE_URL}/v1/models" >/dev/null 2>&1; then
    _REMOTE_MODELS=$(curl -sf "${XGH_REMOTE_URL}/v1/models" \
      | python3 -c "import json,sys; [print(m['id'] + '|' + m['id']) for m in json.load(sys.stdin).get('data',[])]")
    if [ -n "$_REMOTE_MODELS" ]; then
      IFS=$'\n' read -r -d '' -a LLM_MODELS <<< "$_REMOTE_MODELS" || true
      IFS=$'\n' read -r -d '' -a EMBED_MODELS <<< "$_REMOTE_MODELS" || true
    fi
  fi
  ```
  If no models returned, fall back to showing the vllm-mlx model list as reference (with
  a note that these are the expected model IDs for a vllm-mlx server).

### Step 4 — No model download for remote

- [x] Skip the download/pull lane entirely for `remote` backend.

### Step 5 — models.env: store remote URL

- [x] Add `XGH_REMOTE_URL="${XGH_REMOTE_URL}"` to the generated `models.env`.

### Step 6 — cipher.yml + MCP env vars: remote uses openai type with remote baseURL

- [x] Add `remote` branch in the cipher.yml generation and sync blocks.
- [x] Branch `_ENV_ARGS` in the `claude mcp add -s user` call:

  **remote** (provider=openai, remote URL with /v1 suffix):
  ```
  EMBEDDING_PROVIDER=openai   EMBEDDING_MODEL=${XGH_EMBED_MODEL}
  EMBEDDING_BASE_URL=${XGH_REMOTE_URL}/v1   EMBEDDING_API_KEY=placeholder
  OPENAI_API_KEY=placeholder   OPENAI_BASE_URL=${XGH_REMOTE_URL}/v1
  LLM_PROVIDER=openai   LLM_MODEL=${XGH_LLM_MODEL}
  LLM_BASE_URL=${XGH_REMOTE_URL}/v1   LLM_API_KEY=placeholder
  ```
  No `OLLAMA_BASE_URL`. All localhost references replaced with `${XGH_REMOTE_URL}`.

- [x] Same branching in the fallback `_CIPHER_ENV` JSON heredoc.

**Full env key matrix across all backends:**

| Key | `vllm-mlx` | `ollama` | `remote` |
|---|---|---|---|
| `EMBEDDING_PROVIDER` | `openai` | `ollama` | `openai` |
| `EMBEDDING_BASE_URL` | `http://localhost:11434/v1` | `http://localhost:11434` | `${XGH_REMOTE_URL}/v1` |
| `EMBEDDING_API_KEY` | `placeholder` | _(omit)_ | `placeholder` |
| `OPENAI_API_KEY` | `placeholder` | _(omit)_ | `placeholder` |
| `OPENAI_BASE_URL` | `http://localhost:11434/v1` | _(omit)_ | `${XGH_REMOTE_URL}/v1` |
| `OLLAMA_BASE_URL` | _(omit)_ | `http://localhost:11434` | _(omit)_ |
| `LLM_PROVIDER` | `openai` | `ollama` | `openai` |
| `LLM_BASE_URL` | `http://localhost:11434/v1` | `http://localhost:11434` | `${XGH_REMOTE_URL}/v1` |
| `LLM_API_KEY` | `placeholder` | _(omit)_ | `placeholder` |

### Step 7 — ingest-schedule.sh: no model service for remote

- [x] In `install_linux()` and `install_macos()`, skip model server setup when `XGH_BACKEND=remote`.
- [x] `status` subcommand: for remote backend, show connectivity status instead of service status.

### Step 8 — techpack.yaml: add remote component

- [x] Add a `remote-inference` component entry (no install command, just a connectivity check).

### Step 9 — doctor skill: add remote server check

- [x] Update `skills/doctor/doctor.md`: when `XGH_BACKEND=remote`, Check 2 (Connectivity)
  includes a remote server reachability check:
  ```
  Remote inference server
    ✓ http://macmini.local:11434 — reachable, 2 models available
    # OR
    ✗ http://192.168.1.100:11434 — unreachable (timeout)
      Fix: ensure the server is running and port 11434 is accessible from this machine
  ```

### Step 10 — Server side: XGH_SERVE_NETWORK flag

- [x] In `com.xgh.models.plist` template: change `127.0.0.1` to `XGH_MODEL_HOST` placeholder.
- [x] In `ingest-schedule.sh` `_render_plist()`: add `XGH_MODEL_HOST` substitution.
- [x] In `install.sh`, add to models.env render: default `XGH_MODEL_HOST=127.0.0.1`, but
  if `XGH_SERVE_NETWORK=1`, set to `0.0.0.0`.
- [x] Post-install message when serving on network:
  ```
  ✓ vllm-mlx bound to 0.0.0.0:11434
  Other devices can connect via: http://<your-ip>:11434
  On other machines, install xgh with: XGH_BACKEND=remote XGH_REMOTE_URL=http://<your-ip>:11434 bash install.sh
  ```

---

## Risk and Gotcha List

| Risk | Severity | Mitigation |
|---|---|---|
| vllm-mlx on Mac Mini binds to 127.0.0.1 by default — Pi can't reach it | High | `XGH_SERVE_NETWORK=1` on the server side re-renders plist with `0.0.0.0` |
| Raspberry Pi (aarch64) Qdrant binary download must use `aarch64` arch string | High | `ARCH=$(uname -m)` already handles this in Ollama plan Step 2 |
| Remote URL in cipher.yml doesn't end with `/v1` — Cipher may fail | Medium | Installer always appends `/v1` when writing baseURL |
| Firewall blocks port 11434 on Mac Mini | Medium | Post-install message warns user to allow inbound 11434 |
| Remote server down when `xgh-analyze` runs headlessly | Medium | `start-models.sh` checks connectivity; analyzer guard checks Cipher tool availability |
| Model names on remote vllm-mlx include `mlx-community/` prefix | Low | Auto-detect from `/v1/models` returns the actual IDs — no translation needed |
| Ollama remote server uses `ollama` API type, not `openai` compat | Low | Ollama's `/v1/` endpoint is OpenAI-compat — `type: openai` works for both |
