# xgh — Configuration Reference

This document covers every environment variable accepted by the installer, the backend-specific MCP env key matrix, the cipher post-hook behavior, and the pattern for adding a new backend.

---

## Installer Environment Variables

Pass these before `bash install.sh` (or `curl ... | bash`).

### Core

| Variable | Default | Description |
|---|---|---|
| `XGH_TEAM` | `my-team` | Team name written into `CLAUDE.local.md` and agent instructions |
| `XGH_PRESET` | `local` | BYOP provider preset — see [Presets](#byop-presets) |
| `XGH_BACKEND` | _(auto)_ | Inference backend: `vllm-mlx`, `ollama`, or `remote` — see [Backends](#inference-backends) |
| `XGH_REMOTE_URL` | _(none)_ | Required when `XGH_BACKEND=remote`. Full URL of the remote inference server, e.g. `http://192.168.1.x:11434` |
| `XGH_SERVE_NETWORK` | `0` | Set to `1` on the **server side** to bind vllm-mlx to `0.0.0.0:11434` instead of `127.0.0.1`, making it reachable from other devices |
| `XGH_VERSION` | `latest` | xgh release to install |

### Model Selection

| Variable | Default | Description |
|---|---|---|
| `XGH_LLM_MODEL` | _(picker)_ | LLM model ID. Skips the interactive picker when set. Format depends on backend (HuggingFace ID for vllm-mlx, Ollama model name for ollama) |
| `XGH_EMBED_MODEL` | _(picker)_ | Embedding model ID. Same format rules as `XGH_LLM_MODEL` |
| `XGH_MODEL_PORT` | `11434` | Port the local model server listens on |
| `XGH_MODEL_HOST` | `127.0.0.1` | Host the local model server binds to. Set automatically to `0.0.0.0` when `XGH_SERVE_NETWORK=1` |

### Install Behaviour

| Variable | Default | Description |
|---|---|---|
| `XGH_DRY_RUN` | `0` | Set to `1` to run the installer without writing any files or installing dependencies. Safe to run repeatedly for testing. |
| `XGH_LOCAL_PACK` | _(none)_ | Path to a local xgh checkout. When set, installer copies files from this directory instead of downloading from GitHub. Use `.` when working in the repo itself. |
| `XGH_CONTEXT_TREE` | `.xgh/context-tree` | Relative path (from project root) where the context tree is initialised |
| `XGH_INSTALL_PLUGINS` | _(interactive)_ | `all` to install context-mode + superpowers plugins non-interactively; `skip` to skip |
| `XGH_RESET_COLLECTION` | `0` | Set to `1` to delete and recreate the Qdrant `knowledge_memory` collection during install. Use only when switching to a different embedding dimension. |

---

## Inference Backends

Auto-detected at install time. Override with `XGH_BACKEND`.

| Backend | Auto-detected on | Local model server | Qdrant |
|---|---|---|---|
| `vllm-mlx` | macOS Apple Silicon | vllm-mlx (Homebrew, port 11434) | local (Homebrew) |
| `ollama` | Linux / Intel Mac | Ollama (official installer, port 11434) | local (binary download) |
| `remote` | _(never auto)_ | **none** | local (same as ollama path) |

### Backend detection logic

```bash
if XGH_BACKEND=remote (explicit) → remote
elif macOS arm64              → vllm-mlx
else                          → ollama
```

### Network serving (server → client)

On the machine running the model server:
```bash
XGH_SERVE_NETWORK=1 bash install.sh
# ✓ vllm-mlx bound to 0.0.0.0:11434
# Other devices can connect via: http://<your-ip>:11434
```

On the client machine (e.g. Raspberry Pi):
```bash
XGH_BACKEND=remote XGH_REMOTE_URL=http://<server-ip>:11434 bash install.sh
```

---

## MCP / Cipher Env Key Matrix

These env vars are passed to the Cipher MCP server at registration time (`claude mcp add -s user`). They are stored in `~/.claude.json` and do not need to be set manually — the installer writes them based on the backend.

| Key | `vllm-mlx` | `ollama` | `remote` |
|---|---|---|---|
| `EMBEDDING_PROVIDER` | `openai` | `ollama` | `openai` |
| `EMBEDDING_MODEL` | _(from picker)_ | _(from picker)_ | _(from picker)_ |
| `EMBEDDING_BASE_URL` | `http://localhost:11434/v1` | `http://localhost:11434` | `${XGH_REMOTE_URL}/v1` |
| `EMBEDDING_API_KEY` | `placeholder` | _(omit)_ | `placeholder` |
| `OPENAI_API_KEY` | `placeholder` | _(omit)_ | `placeholder` |
| `OPENAI_BASE_URL` | `http://localhost:11434/v1` | _(omit)_ | `${XGH_REMOTE_URL}/v1` |
| `OLLAMA_BASE_URL` | _(omit)_ | `http://localhost:11434` | _(omit)_ |
| `LLM_PROVIDER` | `openai` | `ollama` | `openai` |
| `LLM_MODEL` | _(from picker)_ | _(from picker)_ | _(from picker)_ |
| `LLM_BASE_URL` | `http://localhost:11434/v1` | `http://localhost:11434` | `${XGH_REMOTE_URL}/v1` |
| `LLM_API_KEY` | `placeholder` | _(omit)_ | `placeholder` |

**Note on `/v1` suffix:** vllm-mlx and remote use the OpenAI-compatible `/v1` endpoint. Ollama uses native Cipher support (`type: ollama`) which reads `baseURL` directly without the `/v1` suffix.

---

## BYOP Presets

Set via `XGH_PRESET`. Presets configure the cloud provider for LLM/embeddings and are independent of the inference backend.

| Preset | LLM | Embeddings | Vector store | Cost |
|---|---|---|---|---|
| `local` _(default)_ | backend model | backend model | Qdrant (local) | Free |
| `local-light` | backend model | backend model | In-memory | Free, no persistence |
| `openai` | GPT-4o-mini | text-embedding-3-small | Qdrant (local) | ~$0.01/session |
| `anthropic` | Claude Haiku | backend model | Qdrant (local) | ~$0.01/session |
| `cloud` | OpenRouter | OpenAI embeddings | Qdrant Cloud | ~$0.02/session |

Preset files are in `config/presets/`. Backend selection and preset selection are orthogonal — you can run `XGH_BACKEND=remote XGH_PRESET=openai` to use a remote local server for embeddings while routing LLM calls to OpenAI.

---

## cipher-post-hook

The installer registers `~/.claude/hooks/cipher-post-hook.sh` as a `PostToolUse` hook in `~/.claude/settings.json`. It fires after every `cipher_extract_and_operate_memory` or `cipher_workspace_store` call and detects two failure modes automatically.

### Failure mode 1: `extracted:0` (LLM filtered the content)

Cipher's LLM sometimes filters content and returns `extracted: 0, skipped: N`. The hook detects this and instructs Claude to retry via `qdrant-store.js` directly:

```javascript
const { storeWithDedup } = require(process.env.HOME + '/.local/lib/qdrant-store.js');
const result = await storeWithDedup('knowledge_memory', TEXT, ['tag1'], { domain: 'iOS' });
```

Claude retries automatically — no user action needed.

### Failure mode 2: vector dimension mismatch

When the Qdrant collection was created with a different embedding dimension than the current model, Qdrant rejects upserts. The hook auto-diagnoses by:
1. Querying `GET http://localhost:6333/collections/knowledge_memory` for the collection's vector size
2. Calling the live embedding endpoint with a test string to get the current model's output dimension
3. Presenting a fix table with two options

**Option A — Recreate the collection** (data loss):
```bash
curl -sf -X DELETE http://localhost:6333/collections/knowledge_memory
curl -sf -X PUT http://localhost:6333/collections/knowledge_memory \
  -H 'Content-Type: application/json' \
  -d '{"vectors":{"size":<new-dim>,"distance":"Cosine"}}'
```

**Option B — Switch back to a compatible model** (no data loss):
Edit `~/.cipher/cipher.yml` and set `embedding.model` to a model that outputs the collection's original dimension.

The hook never auto-resets the collection — it always asks the user to choose.

---

## Adding a New Backend

To add a backend beyond `vllm-mlx`, `ollama`, and `remote`:

1. **`install.sh` — platform detection block**: add a branch in the `XGH_BACKEND` detection logic at the top of the file.

2. **`install.sh` — model arrays**: define `<BACKEND>_LLM_MODELS` and `<BACKEND>_EMBED_MODELS` arrays. Hook them into the backend-conditional picker block.

3. **`install.sh` — dependency lane**: add install steps for the model server binary (if any) inside the backend branch.

4. **`install.sh` — download/pull lane**: add a backend-specific model download/pull block.

5. **`install.sh` — `_INFERENCE_BASE`**: set `_INFERENCE_BASE` to the base URL your server uses (with or without `/v1` as appropriate).

6. **`install.sh` — cipher.yml generation**: add a branch writing the correct `llm.provider`, `embedding.type`, and `baseURL` values.

7. **`install.sh` — MCP env vars (`_ENV_ARGS` / `_COMMON_JSON_ENV`)**: add a branch with the correct keys from the [env key matrix](#mcp--cipher-env-key-matrix) pattern.

8. **`install.sh` — `start-models.sh` generation**: add a branch writing the correct startup command.

9. **`scripts/ingest-schedule.sh`**: add backend branches in `install_macos()`, `install_linux()`, and the `status` subcommand.

10. **`techpack.yaml`**: add a component entry with `platform`, `check`, and `when` fields.

11. **`skills/doctor/doctor.md`**: add backend-specific connectivity checks.

12. **`docs/plans/`**: write a plan file documenting the steps (follow the existing plan format).

---

## Runtime Files

These files are written by the installer or at runtime. They are gitignored in user projects.

| File | Description |
|---|---|
| `~/.xgh/models.env` | Persists `XGH_BACKEND`, `XGH_LLM_MODEL`, `XGH_EMBED_MODEL`, `XGH_MODEL_PORT`, `XGH_MODEL_HOST`, `XGH_REMOTE_URL` |
| `~/.xgh/start-models.sh` | Generated startup script — runs the appropriate model server or checks remote connectivity |
| `~/.cipher/cipher.yml` | Cipher MCP server config — LLM provider, embedding type, model names, baseURLs |
| `~/.local/lib/qdrant-store.js` | Low-level Qdrant upsert helper used by the post-hook retry path |
| `~/.claude/hooks/cipher-post-hook.sh` | PostToolUse hook for Cipher failure recovery |
| `.xgh/context-tree/` | Project-level knowledge base (markdown + YAML frontmatter, git-committed) |
| `.xgh/connectors.json` | Connector config (Slack, Jira, GitHub, Figma) — gitignored, machine-specific |
| `.xgh/schedulers/` | Generated launchd plists / systemd unit files — gitignored |
| `.xgh/logs/` | Ingest and model server logs — gitignored |
| `.xgh/inbox/` | Raw retrieval inbox — gitignored |
