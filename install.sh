#!/usr/bin/env bash
set -euo pipefail

XGH_VERSION="${XGH_VERSION:-latest}"
XGH_TEAM="${XGH_TEAM:-my-team}"
XGH_CONTEXT_TREE="${XGH_CONTEXT_TREE:-.xgh/context-tree}"
XGH_PRESET="${XGH_PRESET:-local}"
XGH_DRY_RUN="${XGH_DRY_RUN:-0}"
XGH_LOCAL_PACK="${XGH_LOCAL_PACK:-}"
XGH_REPO="https://github.com/ipedro/xgh"
XGH_LLM_MODEL="${XGH_LLM_MODEL:-}"
XGH_EMBED_MODEL="${XGH_EMBED_MODEL:-}"
XGH_MODEL_PORT="${XGH_MODEL_PORT:-11434}"

# ── Colors ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "  ${GREEN}▸${NC} $*"; }
warn()  { echo -e "  ${YELLOW}▸${NC} $*"; }
error() { echo -e "  ${RED}▸${NC} $*" >&2; }
lane()  { echo ""; echo -e "  ${CYAN}━━━${NC} ${BOLD}$*${NC}"; echo ""; }

echo ""
echo -e "  ${BOLD}🐴🤖 xgh${NC} ${DIM}(eXtreme Go Horse)${NC}"
echo -e "  ${DIM}Team: ${XGH_TEAM} · Preset: ${XGH_PRESET}${NC}"
echo ""

# ── 1. Dependencies ──────────────────────────────────────
if [ "$XGH_DRY_RUN" -eq 0 ]; then
  lane "Saddling up dependencies 🏇"

  if ! command -v brew &>/dev/null; then
    info "Homebrew not found — installing"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # Node.js and npm (required by Cipher MCP wrapper and helper scripts)
  if ! command -v node &>/dev/null; then
    info "Node.js not found — installing via Homebrew"
    brew install node || warn "Could not install Node.js — install manually: brew install node"
  fi

  # Python 3 (required for model downloads and settings merging)
  if ! command -v python3 &>/dev/null; then
    info "Python 3 not found — installing via Homebrew"
    brew install python@3 || warn "Could not install Python 3 — install manually: brew install python@3"
  fi

  # Install uv (Python package installer) if not present
  if ! command -v uv &>/dev/null; then
    info "uv (Python installer)"
    brew install uv
  fi

  # Install vllm-mlx (local model server)
  if ! command -v vllm-mlx &>/dev/null; then
    info "vllm-mlx (local model server for Apple Silicon)"
    uv tool install "git+https://github.com/waybarrios/vllm-mlx.git"
  fi

  # Only install Qdrant for presets that need it
  if [ "$XGH_PRESET" != "local-light" ]; then
    if ! command -v qdrant &>/dev/null && ! [ -x "${HOME}/.qdrant/bin/qdrant" ]; then
      info "Installing Qdrant..."
      brew install qdrant 2>/dev/null || warn "Could not install Qdrant via brew — install manually or ensure ~/.qdrant/bin/qdrant exists"
    fi

    # Fix Qdrant LaunchAgent plist: add MALLOC_CONF and correct WorkingDirectory
    _QDRANT_BIN=$(command -v qdrant 2>/dev/null || echo "${HOME}/.qdrant/bin/qdrant")
    _QDRANT_PLIST="${HOME}/Library/LaunchAgents/com.qdrant.server.plist"
    _QDRANT_STORAGE="${HOME}/.qdrant/storage"
    mkdir -p "${_QDRANT_STORAGE}"
    if [ -f "$_QDRANT_PLIST" ]; then
      # Inject MALLOC_CONF if not already present
      if ! grep -q "MALLOC_CONF" "$_QDRANT_PLIST" 2>/dev/null; then
        python3 - "$_QDRANT_PLIST" <<'PYEOF'
import sys, re
path = sys.argv[1]
content = open(path).read()
if '<key>MALLOC_CONF</key>' not in content:
    inject = '''    <key>EnvironmentVariables</key>
    <dict>
        <key>MALLOC_CONF</key>
        <string>background_thread:false</string>
    </dict>
'''
    content = content.replace('</dict>\n</plist>', inject + '</dict>\n</plist>')
    open(path, 'w').write(content)
    print('Patched MALLOC_CONF into', path)
PYEOF
        info "Qdrant plist: injected MALLOC_CONF=background_thread:false"
      fi
    fi

    # Clear stale WAL locks before starting (harmless if clean)
    find "${_QDRANT_STORAGE}" -path "*/wal/open-*" -delete 2>/dev/null || true

    # Start Qdrant as a background service if not already running
    if ! curl -sf http://localhost:6333/healthz >/dev/null 2>&1; then
      info "Starting Qdrant background service..."
      if [ -f "$_QDRANT_PLIST" ]; then
        launchctl unload "$_QDRANT_PLIST" 2>/dev/null || true
        launchctl load "$_QDRANT_PLIST" 2>/dev/null \
          || warn "Could not load Qdrant plist — start manually: launchctl load ${_QDRANT_PLIST}"
      else
        brew services start qdrant 2>/dev/null || warn "Could not start Qdrant service — start manually: brew services start qdrant"
      fi
    else
      info "Qdrant is already running"
    fi
  fi

  # ── 2. Model Selection ─────────────────────────────────
  lane "Picking brains 🧠"

  # Detect installed models in HuggingFace cache
  HF_CACHE="${HF_HOME:-${HOME}/.cache/huggingface}/hub"
  _model_cached() {
    local slug; slug="models--$(echo "$1" | sed 's|/|--|g')"
    [ -d "${HF_CACHE}/${slug}" ]
  }

  LLM_MODELS=(
    "mlx-community/Llama-3.2-3B-Instruct-4bit|Llama 3.2 3B (default, fast, 2GB)"
    "mlx-community/Llama-3.2-1B-Instruct-4bit|Llama 3.2 1B (tiny, 0.7GB)"
    "mlx-community/Mistral-7B-Instruct-v0.3-4bit|Mistral 7B (powerful, 4GB)"
    "mlx-community/Qwen3-4B-4bit|Qwen3 4B (balanced, 2.5GB)"
    "mlx-community/Qwen3-8B-4bit|Qwen3 8B (strong reasoning, 5GB)"
  )
  EMBED_MODELS=(
    "mlx-community/nomicai-modernbert-embed-base-8bit|ModernBERT Embed 8-bit (default, 768 dims, best quality)"
    "mlx-community/nomicai-modernbert-embed-base-4bit|ModernBERT Embed 4-bit (smaller, 768 dims)"
    "mlx-community/all-MiniLM-L6-v2-4bit|MiniLM L6 (fast, 384 dims)"
  )

  ORIG_DEFAULT_LLM="mlx-community/Llama-3.2-3B-Instruct-4bit"
  ORIG_DEFAULT_EMBED="mlx-community/nomicai-modernbert-embed-base-8bit"

  # Prefer an already-installed model as the default (first installed wins)
  DEFAULT_LLM="$ORIG_DEFAULT_LLM"
  for entry in "${LLM_MODELS[@]}"; do
    IFS='|' read -r mid _ <<< "$entry"
    if _model_cached "$mid"; then
      DEFAULT_LLM="$mid"
      break
    fi
  done

  DEFAULT_EMBED="$ORIG_DEFAULT_EMBED"
  for entry in "${EMBED_MODELS[@]}"; do
    IFS='|' read -r mid _ <<< "$entry"
    if _model_cached "$mid"; then
      DEFAULT_EMBED="$mid"
      break
    fi
  done

  # Find the 1-based index of the default model in a list
  _default_index() {
    local default_id="$1"; shift
    local idx=1
    for entry in "$@"; do
      IFS='|' read -r mid _ <<< "$entry"
      if [ "$mid" = "$default_id" ]; then
        echo "$idx"
        return
      fi
      idx=$((idx + 1))
    done
    echo "1"
  }

  DEFAULT_LLM_IDX=$(_default_index "$DEFAULT_LLM" "${LLM_MODELS[@]}")
  DEFAULT_EMBED_IDX=$(_default_index "$DEFAULT_EMBED" "${EMBED_MODELS[@]}")

  # Interactive model picker (skip if env vars are set)
  if [ -z "$XGH_LLM_MODEL" ]; then
    echo ""
    echo -e "  ${BOLD}Pick an LLM${NC} ${DIM}(Cipher's reasoning brain)${NC}"
    echo ""
    for i in "${!LLM_MODELS[@]}"; do
      IFS='|' read -r model_id model_desc <<< "${LLM_MODELS[$i]}"
      local_tag=""
      if _model_cached "$model_id"; then
        local_tag=" ${GREEN}(installed)${NC}"
      fi
      if [ "$model_id" = "$DEFAULT_LLM" ]; then
        echo -e "    ${GREEN}$((i+1)))${NC} ${model_desc}${local_tag}"
      else
        echo -e "    $((i+1))) ${model_desc}${local_tag}"
      fi
    done
    echo "    c) Custom HuggingFace model ID"
    echo ""
    read -r -p "  🐴 Pick [${DEFAULT_LLM_IDX}]: " llm_choice
    llm_choice="${llm_choice:-$DEFAULT_LLM_IDX}"

    if [ "$llm_choice" = "c" ] || [ "$llm_choice" = "C" ]; then
      read -r -p "  Enter HuggingFace model ID: " XGH_LLM_MODEL
    elif [ "$llm_choice" -ge 1 ] 2>/dev/null && [ "$llm_choice" -le "${#LLM_MODELS[@]}" ]; then
      IFS='|' read -r XGH_LLM_MODEL _ <<< "${LLM_MODELS[$((llm_choice-1))]}"
    else
      XGH_LLM_MODEL="$DEFAULT_LLM"
    fi
  fi
  XGH_LLM_MODEL="${XGH_LLM_MODEL:-$DEFAULT_LLM}"

  if [ -z "$XGH_EMBED_MODEL" ]; then
    echo ""
    echo -e "  ${BOLD}Pick an embedding model${NC} ${DIM}(semantic search engine)${NC}"
    echo ""
    for i in "${!EMBED_MODELS[@]}"; do
      IFS='|' read -r model_id model_desc <<< "${EMBED_MODELS[$i]}"
      local_tag=""
      if _model_cached "$model_id"; then
        local_tag=" ${GREEN}(installed)${NC}"
      fi
      if [ "$model_id" = "$DEFAULT_EMBED" ]; then
        echo -e "    ${GREEN}$((i+1)))${NC} ${model_desc}${local_tag}"
      else
        echo -e "    $((i+1))) ${model_desc}${local_tag}"
      fi
    done
    echo "    c) Custom HuggingFace model ID"
    echo ""
    read -r -p "  🐴 Pick [${DEFAULT_EMBED_IDX}]: " embed_choice
    embed_choice="${embed_choice:-$DEFAULT_EMBED_IDX}"

    if [ "$embed_choice" = "c" ] || [ "$embed_choice" = "C" ]; then
      read -r -p "  Enter HuggingFace model ID: " XGH_EMBED_MODEL
    elif [ "$embed_choice" -ge 1 ] 2>/dev/null && [ "$embed_choice" -le "${#EMBED_MODELS[@]}" ]; then
      IFS='|' read -r XGH_EMBED_MODEL _ <<< "${EMBED_MODELS[$((embed_choice-1))]}"
    else
      XGH_EMBED_MODEL="$DEFAULT_EMBED"
    fi
  fi
  XGH_EMBED_MODEL="${XGH_EMBED_MODEL:-$DEFAULT_EMBED}"

  info "LLM model:       ${XGH_LLM_MODEL}"
  info "Embedding model:  ${XGH_EMBED_MODEL}"

  # ── 3. Download models ─────────────────────────────────
  # _model_cached and HF_CACHE already defined in Model Selection above
  MODELS_TO_DOWNLOAD=()
  for m in "$XGH_LLM_MODEL" "$XGH_EMBED_MODEL"; do
    if _model_cached "$m"; then
      info "Model already cached: ${m}"
    else
      MODELS_TO_DOWNLOAD+=("$m")
    fi
  done

  if [ ${#MODELS_TO_DOWNLOAD[@]} -gt 0 ]; then
    lane "Downloading models (grab a coffee) ☕"
    uv run --with huggingface-hub python3 -c "
from huggingface_hub import snapshot_download
import sys
for model in sys.argv[1:]:
    print(f'  Downloading {model}...')
    try:
        snapshot_download(model)
        print(f'  ✓ {model}')
    except Exception as e:
        print(f'  ⚠ Could not download {model}: {e}')
" "${MODELS_TO_DOWNLOAD[@]}" || warn "Model pre-download failed — models will download on first use"
  else
    info "All models already cached — skipping download"
  fi

  # ── 3b. Cipher Infrastructure ──────────────────────────
  lane "Wiring up the memory layer 🧬"

  # -- install cipher globally if not present --
  if ! command -v cipher &>/dev/null; then
    if command -v npm &>/dev/null; then
      info "Installing Cipher MCP server..."
      npm install -g @byterover/cipher &>/dev/null || {
        warn "Could not install @byterover/cipher — install manually: npm install -g @byterover/cipher"
      }
    else
      warn "npm not found — install Node.js first, then: npm install -g @byterover/cipher"
    fi
  else
    info "Cipher already installed: $(command -v cipher)"
  fi

  # -- cipher-mcp wrapper (filters stdout pollution, injects --agent config, fixes encoding_format) --
  CIPHER_MCP_BIN="${HOME}/.local/bin/cipher-mcp"
  if [ ! -f "$CIPHER_MCP_BIN" ]; then
    info "Setting up cipher-mcp wrapper"
    mkdir -p "${HOME}/.local/bin"
    cat > "$CIPHER_MCP_BIN" <<'CIPHERMCPEOF'
#!/usr/bin/env node
// Wrapper for cipher MCP that:
// 1. Filters stray non-JSON stdout lines (cipher v0.3.0 prints "storeType qdrant")
// 2. Points to user config (~/.cipher/cipher.yml) with correct local embedding model
// 3. Injects HTTP-level fix for OpenAI SDK base64 encoding_format issue via NODE_OPTIONS
const { spawn } = require('child_process');
const path = require('path');

const userConfig = path.join(process.env.HOME, '.cipher', 'cipher.yml');
const httpFix = path.join(process.env.HOME, '.local', 'lib', 'fix-openai-embeddings.js');

const child = spawn('cipher', ['--mode', 'mcp', '--agent', userConfig], {
  stdio: ['pipe', 'pipe', 'inherit'],
  env: {
    ...process.env,
    NODE_OPTIONS: [
      process.env.NODE_OPTIONS || '',
      `--require ${httpFix}`
    ].filter(Boolean).join(' ')
  }
});

// Forward stdin to child
process.stdin.pipe(child.stdin);

// Filter stdout: only pass through lines starting with '{'
let buffer = '';
child.stdout.on('data', (chunk) => {
  buffer += chunk.toString();
  const lines = buffer.split('\n');
  buffer = lines.pop();
  for (const line of lines) {
    if (line.startsWith('{')) {
      process.stdout.write(line + '\n');
    }
  }
});

child.stdout.on('end', () => {
  if (buffer && buffer.startsWith('{')) {
    process.stdout.write(buffer + '\n');
  }
});

child.on('exit', (code) => process.exit(code || 0));
process.on('SIGTERM', () => child.kill('SIGTERM'));
process.on('SIGINT', () => child.kill('SIGINT'));
CIPHERMCPEOF
    chmod +x "$CIPHER_MCP_BIN"
    info "cipher-mcp wrapper → ${CIPHER_MCP_BIN}"
  else
    info "cipher-mcp wrapper already in place"
  fi

  # -- fix-openai-embeddings.js (patches OpenAI SDK encoding_format bug) --
  FIX_EMBED_JS="${HOME}/.local/lib/fix-openai-embeddings.js"
  if [ ! -f "$FIX_EMBED_JS" ]; then
    info "Patching OpenAI SDK embedding compat"
    mkdir -p "${HOME}/.local/lib"
    cat > "$FIX_EMBED_JS" <<'FIXEMBEDEOF'
// Patches OpenAI SDK's Embeddings.create() to inject encoding_format: "float"
// into the body BEFORE the SDK checks hasUserProvidedEncodingFormat.
// This makes the SDK skip its base64 response decoding, fixing vllm-mlx compat.
//
// The SDK flow: create(body) -> checks body.encoding_format -> if absent, adds "base64"
// and decodes response. By injecting "float" into body, the SDK treats it as
// user-provided and returns the response as-is.

const path = require('path');
const fs = require('fs');

// Find the openai module inside cipher's node_modules, resilient to version changes
function findOpenAIRoot() {
  const candidates = [
    // Global npm install (homebrew)
    '/opt/homebrew/lib/node_modules/@byterover/cipher/node_modules/openai',
    // Global npm install (default)
    path.join(process.env.HOME || '', '.npm-global/lib/node_modules/@byterover/cipher/node_modules/openai'),
    // npx / local
    path.join(process.env.HOME || '', 'node_modules/@byterover/cipher/node_modules/openai'),
  ];
  for (const candidate of candidates) {
    try {
      if (fs.existsSync(path.join(candidate, 'resources/embeddings.js'))) {
        return candidate;
      }
    } catch {}
  }
  return null;
}

const OPENAI_ROOT = findOpenAIRoot();

if (OPENAI_ROOT) {
  try {
    const embeddings = require(OPENAI_ROOT + '/resources/embeddings.js');
    if (embeddings && embeddings.Embeddings && embeddings.Embeddings.prototype) {
      const origCreate = embeddings.Embeddings.prototype.create;
      embeddings.Embeddings.prototype.create = function(body, options) {
        if (!body.encoding_format) {
          body = { ...body, encoding_format: 'float' };
        }
        return origCreate.call(this, body, options);
      };
      process.stderr.write('[fix-openai-embeddings] Patched Embeddings.create (encoding_format: float)\n');
    }
  } catch (e) {
    process.stderr.write('[fix-openai-embeddings] Failed to patch: ' + e.message + '\n');
  }
} else {
  process.stderr.write('[fix-openai-embeddings] OpenAI SDK not found in cipher node_modules\n');
}
FIXEMBEDEOF
    info "Embedding fix → ${FIX_EMBED_JS}"
  else
    info "Embedding fix already in place"
  fi

  # -- qdrant-store.js (direct Qdrant storage, bypasses cipher's LLM extraction) --
  QDRANT_STORE_JS="${HOME}/.local/lib/qdrant-store.js"
  if [ ! -f "$QDRANT_STORE_JS" ]; then
    info "Setting up direct Qdrant storage helper"
    mkdir -p "${HOME}/.local/lib"
    cat > "$QDRANT_STORE_JS" <<'QDRANTSTOREEOF'
#!/usr/bin/env node
// Direct Qdrant memory storage — bypasses cipher's LLM extraction layer.
// Only uses the embedding model (vllm-mlx) for vector generation.
// Reads config from ~/.cipher/cipher.yml for model/endpoint.

const http = require('http');
const fs = require('fs');
const path = require('path');

function getConfig() {
  const defaults = {
    model: 'mlx-community/nomicai-modernbert-embed-base-8bit',
    baseURL: 'http://localhost:11434/v1',
    dimensions: 768,
    qdrantURL: 'http://localhost:6333'
  };
  try {
    const content = fs.readFileSync(path.join(process.env.HOME, '.cipher', 'cipher.yml'), 'utf8');
    // Extract the embedding: section specifically (between "embedding:" and next top-level key)
    const embeddingSection = content.match(/^embedding:\s*\n((?:\s+.+\n?)*)/m);
    if (embeddingSection) {
      const section = embeddingSection[1];
      const modelMatch = section.match(/model:\s*(.+)/);
      const baseURLMatch = section.match(/baseURL:\s*(.+)/);
      const dimsMatch = section.match(/dimensions:\s*(\d+)/);
      return {
        model: modelMatch ? modelMatch[1].trim() : defaults.model,
        baseURL: baseURLMatch ? baseURLMatch[1].trim() : defaults.baseURL,
        dimensions: dimsMatch ? parseInt(dimsMatch[1]) : defaults.dimensions,
        qdrantURL: defaults.qdrantURL
      };
    }
    return defaults;
  } catch {
    return defaults;
  }
}

function httpReq(method, url, data) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const body = data ? JSON.stringify(data) : null;
    const opts = {
      hostname: u.hostname, port: u.port, path: u.pathname + u.search, method,
      headers: { 'Content-Type': 'application/json' }
    };
    if (body) opts.headers['Content-Length'] = Buffer.byteLength(body);
    const req = http.request(opts, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => { try { resolve(JSON.parse(d)); } catch { resolve(d); } });
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

async function embed(text) {
  const config = getConfig();
  const r = await httpReq('POST', `${config.baseURL}/embeddings`, {
    input: text, model: config.model, encoding_format: 'float'
  });
  if (!r.data || !r.data[0]) throw new Error('Embedding failed: ' + JSON.stringify(r));
  return r.data[0].embedding;
}

async function search(query, collection, topK, threshold) {
  collection = collection || 'knowledge_memory';
  topK = topK || 3;
  threshold = threshold || 0.3;
  const config = getConfig();
  const vector = await embed(query);
  const r = await httpReq('POST', `${config.qdrantURL}/collections/${collection}/points/search`, {
    vector, limit: topK, score_threshold: threshold, with_payload: true
  });
  return r.result || [];
}

async function store(collection, id, text, tags, metadata) {
  metadata = metadata || {};
  const config = getConfig();
  const vector = await embed(text);
  return httpReq('PUT', `${config.qdrantURL}/collections/${collection}/points`, {
    points: [{
      id, vector,
      payload: {
        text, tags: tags || [], timestamp: new Date().toISOString(),
        event: 'ADD', confidence: 0.95,
        domain: metadata.domain || 'general',
        source: metadata.source || 'direct-store',
        projectId: metadata.projectId || '',
        ...metadata
      }
    }]
  });
}

async function storeWithDedup(collection, text, tags, metadata) {
  metadata = metadata || {};
  const existing = await search(text, collection, 1, 0.85);
  if (existing.length > 0) {
    return { action: 'SKIP', reason: 'Similar entry exists (similarity: ' + existing[0].score.toFixed(3) + ')', existingId: existing[0].id };
  }
  const id = Date.now() + Math.floor(Math.random() * 1000);
  const result = await store(collection, id, text, tags, metadata);
  return { action: 'ADD', id, status: result.status };
}

if (require.main === module) {
  const [cmd, ...args] = process.argv.slice(2);
  const run = async () => {
    switch (cmd) {
      case 'config': return console.log(JSON.stringify(getConfig(), null, 2));
      case 'embed': return console.log(JSON.stringify({ dims: (await embed(args[0])).length }));
      case 'search': return console.log(JSON.stringify(await search(args[0], args[1], parseInt(args[2]) || 3), null, 2));
      case 'store': return console.log(JSON.stringify(await storeWithDedup(args[0] || 'knowledge_memory', args[1], args[2] ? args[2].split(',') : [], { domain: args[3] || 'general' }), null, 2));
      default: console.log('Usage: qdrant-store.js <config|embed|search|store> [args...]');
    }
  };
  run().catch(e => { console.error(e.message); process.exit(1); });
}

module.exports = { embed, search, store, storeWithDedup, getConfig };
QDRANTSTOREEOF
    chmod +x "$QDRANT_STORE_JS"
    info "qdrant-store → ${QDRANT_STORE_JS}"
  else
    info "qdrant-store already in place"
  fi

  # -- cipher.yml (cipher agent config with correct models and endpoints) --
  CIPHER_YML="${HOME}/.cipher/cipher.yml"
  if [ ! -f "$CIPHER_YML" ]; then
    info "Generating cipher.yml"
    mkdir -p "${HOME}/.cipher"
    cat > "$CIPHER_YML" <<CIPHERYMLEOF
mcpServers: {}

llm:
  provider: openai
  model: ${XGH_LLM_MODEL}
  maxIterations: 50
  apiKey: placeholder
  baseURL: http://localhost:${XGH_MODEL_PORT}/v1

embedding:
  type: openai
  model: ${XGH_EMBED_MODEL}
  apiKey: placeholder
  baseURL: http://localhost:${XGH_MODEL_PORT}/v1
  dimensions: 768

systemPrompt:
  enabled: true
  content: |
    You are an AI programming assistant focused on coding and reasoning tasks. You excel at:
    - Writing clean, efficient code
    - Debugging and problem-solving
    - Code review and optimization
    - Explaining complex technical concepts
    - Reasoning through programming challenges
CIPHERYMLEOF
    info "cipher.yml → ${CIPHER_YML}"
  else
    # Update model names in existing cipher.yml to match current selection
    info "cipher.yml exists — syncing model names"
    python3 - "$CIPHER_YML" "$XGH_LLM_MODEL" "$XGH_EMBED_MODEL" "$XGH_MODEL_PORT" <<'SYNCEOF'
import sys, re
path, llm_model, embed_model, port = sys.argv[1:]
content = open(path).read()
# Update embedding model
content = re.sub(r'(^embedding:.*?^\s+model:\s*)(\S+)', lambda m: m.group(1) + embed_model, content, flags=re.MULTILINE|re.DOTALL, count=1)
# Update LLM model (only under llm: section, not embedding:)
content = re.sub(r'(^llm:.*?^\s+model:\s*)(\S+)', lambda m: m.group(1) + llm_model, content, flags=re.MULTILINE|re.DOTALL, count=1)
# Update port in baseURLs
content = re.sub(r'(baseURL:\s*http://localhost:)\d+', lambda m: m.group(1) + port, content)
open(path, 'w').write(content)
print(f'  synced: llm={llm_model} embed={embed_model} port={port}')
SYNCEOF
  fi

  # -- Qdrant collections (768-dim Cosine vectors) --
  ensure_qdrant_collections() {
    local qdrant_url="http://localhost:6333"

    # Wait for Qdrant to become ready (max 5 seconds)
    local retries=5
    while [ "$retries" -gt 0 ]; do
      if curl -sf "${qdrant_url}/healthz" >/dev/null 2>&1; then
        break
      fi
      info "Waiting for Qdrant to become ready... (${retries}s remaining)"
      sleep 1
      retries=$((retries - 1))
    done

    if ! curl -sf "${qdrant_url}/collections" >/dev/null 2>&1; then
      warn "Qdrant not reachable after waiting — collections will be created on first use"
      return 0
    fi

    for collection in knowledge_memory workspace_memory reflection_memory xgh-workspace; do
      if curl -sf "${qdrant_url}/collections/${collection}" >/dev/null 2>&1; then
        info "Qdrant collection '${collection}' already exists"
      else
        info "Creating Qdrant collection '${collection}' (768-dim Cosine)..."
        curl -sf -X PUT "${qdrant_url}/collections/${collection}" \
          -H 'Content-Type: application/json' \
          -d '{
            "vectors": {
              "size": 768,
              "distance": "Cosine"
            }
          }' >/dev/null 2>&1 && info "Created '${collection}'" || warn "Could not create '${collection}'"
      fi
    done
  }
  ensure_qdrant_collections

  # -- Post-install Cipher health check --
  _cipher_checks=0
  _cipher_total=4
  command -v cipher &>/dev/null && _cipher_checks=$((_cipher_checks + 1))
  [ -f "${HOME}/.cipher/cipher.yml" ] && _cipher_checks=$((_cipher_checks + 1))
  [ -x "$CIPHER_MCP_BIN" ] && _cipher_checks=$((_cipher_checks + 1))
  curl -sf "http://localhost:6333/healthz" >/dev/null 2>&1 && _cipher_checks=$((_cipher_checks + 1))
  if [ "$_cipher_checks" -eq "$_cipher_total" ]; then
    info "Cipher ready: binary ✓ config ✓ wrapper ✓ Qdrant ✓"
  else
    warn "Cipher ${_cipher_checks}/${_cipher_total} checks passed — run /xgh-doctor after launching Claude"
  fi

else
  info "Dry run — skipping the heavy lifting 🏋️"
  XGH_LLM_MODEL="${XGH_LLM_MODEL:-mlx-community/Llama-3.2-3B-Instruct-4bit}"
  XGH_EMBED_MODEL="${XGH_EMBED_MODEL:-mlx-community/nomicai-modernbert-embed-base-8bit}"
fi

# ── 3. Fetch xgh pack ───────────────────────────────────
lane "Fetching the tech pack 📦"
if [ -n "$XGH_LOCAL_PACK" ]; then
  PACK_DIR="$XGH_LOCAL_PACK"
  info "Using local pack: ${PACK_DIR}"
else
  PACK_DIR="${HOME}/.xgh/pack"
  info "Pulling from the ranch..."
  mkdir -p "$(dirname "$PACK_DIR")"

  if [ -d "$PACK_DIR" ]; then
    git -C "$PACK_DIR" pull --quiet 2>/dev/null || warn "Could not update pack"
  else
    git clone --quiet --depth 1 "$XGH_REPO" "$PACK_DIR"
  fi
fi

# ── 4. Cipher MCP Server ────────────────────────────────
lane "Configuring Cipher MCP 🔮"
CLAUDE_DIR="${PWD}/.claude"
mkdir -p "${CLAUDE_DIR}"

# Read preset for env vars
PRESET_FILE="${PACK_DIR}/config/presets/${XGH_PRESET}.yaml"
if [ ! -f "$PRESET_FILE" ]; then
  error "Unknown preset: ${XGH_PRESET}"
  error "Available: local, local-light, openai, anthropic, cloud"
  exit 1
fi

# Extract vector store type and URL from preset (simple parsing)
VS_TYPE=$(grep 'type:' "$PRESET_FILE" | tail -1 | awk '{print $2}')
VS_URL=$(grep 'url:' "$PRESET_FILE" | tail -1 | awk '{print $2}' || echo "")
# Detect local vs cloud inference by checking if preset uses a localhost base URL
PRESET_LLM_URL=$(grep 'baseUrl:\|base_url:' "$PRESET_FILE" | head -1 | awk '{print $2}' 2>/dev/null || echo "")

# Register Cipher MCP globally — use Claude CLI when available, else write file directly
_OLLAMA_ENV=""
if echo "$PRESET_LLM_URL" | grep -q "localhost\|127\.0\.0\.1"; then
  _OLLAMA_ENV="OLLAMA_BASE_URL=http://localhost:${XGH_MODEL_PORT}"
fi

if command -v claude &>/dev/null && [ "$XGH_DRY_RUN" -eq 0 ]; then
  # Use the CLI: writes to ~/.claude/.mcp.json with -s user (available in all projects)
  _ENV_ARGS=(
    -e "MCP_SERVER_MODE=aggregator"
    -e "VECTOR_STORE_TYPE=${VS_TYPE}"
    -e "VECTOR_STORE_URL=${VS_URL}"
    -e "EMBEDDING_PROVIDER=openai"
    -e "EMBEDDING_MODEL=${XGH_EMBED_MODEL}"
    -e "EMBEDDING_BASE_URL=http://localhost:${XGH_MODEL_PORT}/v1"
    -e "EMBEDDING_DIMENSIONS=768"
    -e "EMBEDDING_API_KEY=placeholder"
    -e "OPENAI_API_KEY=placeholder"
    -e "OPENAI_BASE_URL=http://localhost:${XGH_MODEL_PORT}/v1"
    -e "LLM_PROVIDER=openai"
    -e "LLM_MODEL=${XGH_LLM_MODEL}"
    -e "LLM_BASE_URL=http://localhost:${XGH_MODEL_PORT}/v1"
    -e "LLM_API_KEY=placeholder"
    -e "CIPHER_LOG_LEVEL=info"
    -e "SEARCH_MEMORY_TYPE=both"
    -e "USE_WORKSPACE_MEMORY=true"
    -e "XGH_TEAM=${XGH_TEAM}"
  )
  [ -n "$_OLLAMA_ENV" ] && _ENV_ARGS+=(-e "$_OLLAMA_ENV")
  claude mcp remove cipher -s user 2>/dev/null || true
  # name and commandOrUrl must come before -e flags
  claude mcp add -s user cipher "${HOME}/.local/bin/cipher-mcp" "${_ENV_ARGS[@]}"
  info "Cipher MCP ✓ registered globally (claude mcp add -s user)"
else
  # Fallback: write ~/.claude.json directly (dry-run or claude not yet in PATH)
  _GLOBAL_CLAUDE_JSON="${HOME}/.claude.json"
  _CIPHER_ENV=$(cat <<ENVEOF
{
  "MCP_SERVER_MODE": "aggregator",
  "VECTOR_STORE_TYPE": "${VS_TYPE}",
  "VECTOR_STORE_URL": "${VS_URL}",
  "EMBEDDING_PROVIDER": "openai",
  "EMBEDDING_MODEL": "${XGH_EMBED_MODEL}",
  "EMBEDDING_BASE_URL": "http://localhost:${XGH_MODEL_PORT}/v1",
  "EMBEDDING_DIMENSIONS": "768",
  "EMBEDDING_API_KEY": "placeholder",
  "OPENAI_API_KEY": "placeholder",
  "OPENAI_BASE_URL": "http://localhost:${XGH_MODEL_PORT}/v1",
  "LLM_PROVIDER": "openai",
  "LLM_MODEL": "${XGH_LLM_MODEL}",
  "LLM_BASE_URL": "http://localhost:${XGH_MODEL_PORT}/v1",
  "LLM_API_KEY": "placeholder",
  "CIPHER_LOG_LEVEL": "info",
  "SEARCH_MEMORY_TYPE": "both",
  "USE_WORKSPACE_MEMORY": "true",
  "XGH_TEAM": "${XGH_TEAM}"
}
ENVEOF
)
  [ -n "$_OLLAMA_ENV" ] && _CIPHER_ENV=$(echo "$_CIPHER_ENV" | jq \
    --arg v "http://localhost:${XGH_MODEL_PORT}" '.OLLAMA_BASE_URL = $v')
  _CIPHER_ENTRY=$(echo "$_CIPHER_ENV" | jq \
    --arg cmd "${HOME}/.local/bin/cipher-mcp" \
    '{"type":"stdio","command":$cmd,"args":[],"env":.}')
  if [ -f "$_GLOBAL_CLAUDE_JSON" ] && [ -s "$_GLOBAL_CLAUDE_JSON" ]; then
    jq --argjson e "$_CIPHER_ENTRY" '.mcpServers.cipher = $e' \
      "$_GLOBAL_CLAUDE_JSON" > "${_GLOBAL_CLAUDE_JSON}.tmp" \
      && mv "${_GLOBAL_CLAUDE_JSON}.tmp" "$_GLOBAL_CLAUDE_JSON"
  else
    echo '{"mcpServers":{}}' | jq --argjson e "$_CIPHER_ENTRY" \
      '.mcpServers.cipher = $e' > "$_GLOBAL_CLAUDE_JSON"
  fi
  info "Cipher MCP → ~/.claude.json"
fi

# Clean up any legacy project-level .mcp.json
if [ -f "${PWD}/.mcp.json" ]; then
  LEGACY_KEYS=$(jq -r '.mcpServers | keys[]' "${PWD}/.mcp.json" 2>/dev/null || echo "")
  if [ "$LEGACY_KEYS" = "cipher" ]; then
    rm -f "${PWD}/.mcp.json"
    info "Removed legacy .mcp.json (cipher now global)"
  elif echo "$LEGACY_KEYS" | grep -q "cipher"; then
    jq 'del(.mcpServers.cipher)' "${PWD}/.mcp.json" > "${PWD}/.mcp.json.tmp" \
      && mv "${PWD}/.mcp.json.tmp" "${PWD}/.mcp.json"
    info "Removed cipher from project .mcp.json (now global)"
  fi
fi

# ── 5. Hooks ────────────────────────────────────────────
XGH_HOOKS_SCOPE="${XGH_HOOKS_SCOPE:-}"

if [ -z "$XGH_HOOKS_SCOPE" ] && [ "$XGH_DRY_RUN" -eq 0 ]; then
  echo ""
  echo -e "  ${BOLD}Where should the horse roam?${NC}"
  echo ""
  echo -e "    1) ${GREEN}Global${NC} (~/.claude) — works in all projects ${DIM}(recommended)${NC}"
  echo "    2) Project (.claude) — only this project"
  echo ""
  read -r -p "  🐴 Pick [1]: " hooks_choice
  hooks_choice="${hooks_choice:-1}"
  if [ "$hooks_choice" = "2" ]; then
    XGH_HOOKS_SCOPE="project"
  else
    XGH_HOOKS_SCOPE="global"
  fi
elif [ -z "$XGH_HOOKS_SCOPE" ]; then
  XGH_HOOKS_SCOPE="global"
fi

lane "Hooking into Claude Code 🪝"
if [ "$XGH_HOOKS_SCOPE" = "global" ]; then
  HOOKS_DIR="${HOME}/.claude/hooks"
  SETTINGS_FILE="${HOME}/.claude/settings.json"
  HOOKS_CMD_PREFIX="~/.claude/hooks"
  info "Hooks → global (~/.claude/hooks)"
else
  HOOKS_DIR="${CLAUDE_DIR}/hooks"
  SETTINGS_FILE="${CLAUDE_DIR}/settings.local.json"
  HOOKS_CMD_PREFIX=".claude/hooks"
  info "Hooks → project (.claude/hooks)"
fi

mkdir -p "${HOOKS_DIR}"

# Copy hook files (or create placeholders if not in pack yet)
for hook in session-start prompt-submit; do
  src="${PACK_DIR}/hooks/${hook}.sh"
  dst="${HOOKS_DIR}/xgh-${hook}.sh"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
  else
    # Placeholder hook
    cat > "$dst" <<'HOOKEOF'
#!/usr/bin/env bash
# xgh placeholder hook
exit 0
HOOKEOF
  fi
  chmod +x "$dst"
done

# -- Cipher Pre/PostToolUse hooks (detect extraction failures, suggest direct storage) --
info "Adding cipher safety nets..."

cat > "${HOOKS_DIR}/cipher-pre-hook.sh" <<'PREHOOKEOF'
#!/bin/bash
# PreToolUse hook for cipher memory tools.
# Detects structured/complex content that cipher's 3B extraction model
# will likely reject, and suggests direct Qdrant storage instead.

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null)

case "$tool_name" in
  mcp__cipher__cipher_extract_and_operate_memory|mcp__cipher__cipher_workspace_store)
    ;;
  *)
    exit 0
    ;;
esac

analysis=$(echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    inp = data.get('tool_input', {})
    interaction = inp.get('interaction', '')
    if isinstance(interaction, list):
        interaction = ' '.join(interaction)

    reasons = []
    length = len(interaction)

    if length > 500:
        reasons.append(f'long ({length} chars)')
    if interaction.count('#') >= 2:
        reasons.append('markdown headers')
    if '|' in interaction and interaction.count('|') >= 6:
        reasons.append('tables')
    if '\`\`\`' in interaction:
        reasons.append('code blocks')
    if interaction.count(chr(10)) > 10:
        reasons.append(f'{interaction.count(chr(10))} lines')

    if reasons:
        print('COMPLEX:' + '; '.join(reasons))
    else:
        print('SIMPLE')
except:
    print('SIMPLE')
" 2>/dev/null)

if [[ "$analysis" == COMPLEX* ]]; then
    reason="${analysis#COMPLEX:}"
    read -r -d '' CONTEXT << MARKDOWN
Warning: **Cipher extraction warning**: Content is structured/complex ($reason). Cipher's 3B model will likely filter this (extracted:0).

**Recommended**: Use \`/store-memory\` skill or store directly via \`ctx_execute\` with:
\`\`\`javascript
const { storeWithDedup } = require(process.env.HOME + '/.local/lib/qdrant-store.js');
\`\`\`
MARKDOWN

    jq -n --arg ctx "$CONTEXT" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            additionalContext: $ctx
        }
    }'
fi
PREHOOKEOF
chmod +x "${HOOKS_DIR}/cipher-pre-hook.sh"

cat > "${HOOKS_DIR}/cipher-post-hook.sh" <<'POSTHOOKEOF'
#!/bin/bash
# PostToolUse hook for cipher memory tools.
# Detects two failure modes and instructs Claude on recovery:
#   1. extracted:0  — cipher's LLM filtered the content → retry via qdrant-store.js
#   2. dimension mismatch — embedding model dims don't match Qdrant collection → diagnose + fix

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null)

case "$tool_name" in
  mcp__cipher__cipher_extract_and_operate_memory|mcp__cipher__cipher_workspace_store)
    ;;
  *)
    exit 0
    ;;
esac

result=$(echo "$input" | jq -r '.tool_result // empty' 2>/dev/null)

diagnosis=$(echo "$result" | python3 -c "
import sys, json, re

def decode(raw):
    raw = raw.strip()
    try:
        return json.loads(json.loads(raw))
    except (json.JSONDecodeError, TypeError):
        try:
            return json.loads(raw)
        except Exception:
            return {'_raw': raw}

raw = sys.stdin.read()
data = decode(raw)
raw_str = str(data)

# --- Check 1: dimension mismatch ---
dim_pattern = re.search(r'[Vv]ector dimension[^;]*expected\s*(?:dim:?\s*)?(\d+)[^;]*got\s*(\d+)', raw_str)
if not dim_pattern:
    dim_pattern = re.search(r'expected\s*dim[:\s]+(\d+)[,\s]+got\s*(\d+)', raw_str)
if dim_pattern:
    expected, got = dim_pattern.group(1), dim_pattern.group(2)
    print(f'DIM_MISMATCH:{expected}:{got}')
    sys.exit(0)

if 'dimension' in raw_str.lower() and ('error' in raw_str.lower() or 'wrong' in raw_str.lower()):
    print('DIM_MISMATCH:unknown:unknown')
    sys.exit(0)

# --- Check 2: extracted:0 ---
ext = data.get('extraction', {})
extracted = ext.get('extracted', -1)
skipped = ext.get('skipped', 0)

if extracted == -1:
    workspace = data.get('workspace', None)
    if isinstance(workspace, list) and len(workspace) == 0:
        extracted = 0
        skipped = max(skipped, 1)

if extracted == 0 and skipped > 0:
    print(f'EXTRACTED_ZERO:{skipped}')
    sys.exit(0)

print('OK')
" 2>/dev/null)

# ── Dimension mismatch ───────────────────────────────────────────────────────
if [[ "$diagnosis" == DIM_MISMATCH:* ]]; then
    IFS=':' read -r _ expected_dim got_dim <<< "$diagnosis"

    collection_dim=$(python3 -c "
import urllib.request, json
try:
    r = urllib.request.urlopen('http://localhost:6333/collections/knowledge_memory', timeout=3)
    d = json.load(r)
    print(d['result']['config']['params']['vectors']['size'])
except Exception:
    print('unknown')
" 2>/dev/null)

    model_dim=$(python3 -c "
import urllib.request, json, os
try:
    import yaml
    cfg = yaml.safe_load(open(os.path.expanduser('~/.cipher/cipher.yml')))
    model = cfg.get('embedding', {}).get('model', 'unknown')
    base = cfg.get('embedding', {}).get('baseURL', 'http://localhost:11434/v1')
    data = json.dumps({'input': 'test', 'model': model, 'encoding_format': 'float'}).encode()
    req = urllib.request.Request(base + '/embeddings', data=data,
        headers={'Content-Type': 'application/json'})
    resp = urllib.request.urlopen(req, timeout=5)
    result = json.load(resp)
    print(len(result['data'][0]['embedding']))
except Exception:
    print('unknown')
" 2>/dev/null)

    cipher_model=$(python3 -c "
import yaml, os
try:
    cfg = yaml.safe_load(open(os.path.expanduser('~/.cipher/cipher.yml')))
    print(cfg.get('embedding', {}).get('model', 'unknown'))
except Exception:
    print('unknown')
" 2>/dev/null)

    read -r -d '' CONTEXT << MARKDOWN
**Cipher vector dimension mismatch** — Qdrant rejected the embedding.

| | Value |
|---|---|
| Qdrant collection expects | **${collection_dim} dims** |
| Current embedding model outputs | **${model_dim} dims** (model: \`${cipher_model}\`) |

**Root cause:** The embedding model was changed after the collection was created with different dimensions. Qdrant collections have a fixed vector size.

**Fix options:**

**Option A — Recreate the collection** (data loss — all stored memories are deleted):
\`\`\`bash
curl -sf -X DELETE http://localhost:6333/collections/knowledge_memory
curl -sf -X PUT http://localhost:6333/collections/knowledge_memory \
  -H 'Content-Type: application/json' \
  -d '{"vectors":{"size":${model_dim},"distance":"Cosine"}}'
\`\`\`
Then retry the original store operation.

**Option B — Switch back to a compatible embedding model** (no data loss):
Edit \`~/.cipher/cipher.yml\` and set \`embedding.model\` to a model that outputs ${collection_dim} dims, then restart the cipher-mcp process.

**Do NOT retry the current operation until one of the above is resolved.** Ask the user which option they prefer.
MARKDOWN

    jq -n --arg ctx "$CONTEXT" '{
        hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: $ctx
        }
    }'
    exit 0
fi

# ── Extracted zero ───────────────────────────────────────────────────────────
if [[ "$diagnosis" == EXTRACTED_ZERO:* ]]; then
    skipped="${diagnosis#EXTRACTED_ZERO:}"
    read -r -d '' CONTEXT << MARKDOWN
**Cipher extraction failed** (extracted=0, skipped=${skipped}). The LLM filtered out the content.

**You MUST store this directly.** Use \`ctx_execute\` with JavaScript:
\`\`\`javascript
const { storeWithDedup } = require(process.env.HOME + '/.local/lib/qdrant-store.js');
const result = await storeWithDedup('knowledge_memory', TEXT, ['tag1'], { domain: 'iOS', projectId: 'acme-ios' });
console.log(JSON.stringify(result));
\`\`\`
Pass the ORIGINAL text that was meant to be stored. Do NOT ask the user — just retry automatically.
MARKDOWN

    jq -n --arg ctx "$CONTEXT" '{
        hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: $ctx
        }
    }'
fi
POSTHOOKEOF
chmod +x "${HOOKS_DIR}/cipher-post-hook.sh"

# ── 6. Settings ─────────────────────────────────────────
lane "Tuning permissions ⚙️"
# SETTINGS_FILE was set in section 5 based on scope

HOOKS_SETTINGS="${PACK_DIR}/config/hooks-settings.json"
PERMS_SETTINGS="${PACK_DIR}/config/settings.json"

# Resolve hook command paths from template placeholder
RESOLVED_HOOKS=$(python3 -c "
import json
with open('${HOOKS_SETTINGS}') as f:
    data = json.load(f)
# Replace __HOOKS_DIR__ placeholder with actual path
raw = json.dumps(data)
raw = raw.replace('__HOOKS_DIR__', '${HOOKS_CMD_PREFIX}')
print(raw)
" 2>/dev/null)

if [ -f "$SETTINGS_FILE" ] && [ -s "$SETTINGS_FILE" ]; then
  # Merge: existing + hooks + permissions
  python3 -c "
import json, sys
base = json.load(open('${SETTINGS_FILE}'))
hooks_data = json.loads('''${RESOLVED_HOOKS}''')
perms_data = json.load(open('${PERMS_SETTINGS}'))
for overlay in [hooks_data, perms_data]:
    for k, v in overlay.items():
        if k in base and isinstance(base[k], dict) and isinstance(v, dict):
            base[k].update(v)
        else:
            base[k] = v
json.dump(base, open('${SETTINGS_FILE}', 'w'), indent=2)
" 2>/dev/null || {
    warn "Could not merge settings — writing fresh"
    python3 -c "
import json
hooks_data = json.loads('''${RESOLVED_HOOKS}''')
perms_data = json.load(open('${PERMS_SETTINGS}'))
merged = {**hooks_data, **perms_data}
json.dump(merged, open('${SETTINGS_FILE}', 'w'), indent=2)
" 2>/dev/null
  }
else
  # No existing settings — merge hooks + permissions
  python3 -c "
import json
hooks_data = json.loads('''${RESOLVED_HOOKS}''')
perms_data = json.load(open('${PERMS_SETTINGS}'))
merged = {**hooks_data, **perms_data}
json.dump(merged, open('${SETTINGS_FILE}', 'w'), indent=2)
" 2>/dev/null
fi

# Add cipher Pre/PostToolUse hooks to settings
python3 -c "
import json
settings = json.load(open('${SETTINGS_FILE}'))
hooks = settings.setdefault('hooks', {})
cipher_matcher = 'mcp__cipher__cipher_extract_and_operate_memory|mcp__cipher__cipher_workspace_store'

# Add PreToolUse hook if not already present
if 'PreToolUse' not in hooks:
    hooks['PreToolUse'] = []
pre_exists = any(
    cipher_matcher in str(h.get('matcher', ''))
    for h in hooks.get('PreToolUse', [])
)
if not pre_exists:
    hooks['PreToolUse'].append({
        'matcher': cipher_matcher,
        'hooks': [{'type': 'command', 'command': 'bash ${HOOKS_CMD_PREFIX}/cipher-pre-hook.sh'}]
    })

# Add PostToolUse hook if not already present
if 'PostToolUse' not in hooks:
    hooks['PostToolUse'] = []
post_exists = any(
    cipher_matcher in str(h.get('matcher', ''))
    for h in hooks.get('PostToolUse', [])
)
if not post_exists:
    hooks['PostToolUse'].append({
        'matcher': cipher_matcher,
        'hooks': [{'type': 'command', 'command': 'bash ${HOOKS_CMD_PREFIX}/cipher-post-hook.sh'}]
    })

json.dump(settings, open('${SETTINGS_FILE}', 'w'), indent=2)
" 2>/dev/null || warn "Could not add cipher hooks to settings — add them manually"

# ── 7. Skills + Commands + Agents ────────────────────────
# Respect the same scope choice as hooks (global vs project)
lane "Teaching the horse new tricks 🎓"
if [ "$XGH_HOOKS_SCOPE" = "global" ]; then
  INSTALL_DIR="${HOME}/.claude"
  info "Skills, commands, agents → global (~/.claude)"
else
  INSTALL_DIR="${CLAUDE_DIR}"
  info "Skills, commands, agents → project (.claude)"
fi

mkdir -p "${INSTALL_DIR}/skills" "${INSTALL_DIR}/commands" "${INSTALL_DIR}/agents"

for skill_dir in "${PACK_DIR}/skills/"*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  [ "$skill_name" = ".gitkeep" ] && continue
  cp -r "$skill_dir" "${INSTALL_DIR}/skills/xgh-${skill_name}"
done

for cmd in "${PACK_DIR}/commands/"*.md; do
  [ -f "$cmd" ] || continue
  cp "$cmd" "${INSTALL_DIR}/commands/xgh-$(basename "$cmd")"
done

for agent in "${PACK_DIR}/agents/"*.md; do
  [ -f "$agent" ] || continue
  cp "$agent" "${INSTALL_DIR}/agents/xgh-$(basename "$agent")"
done

# -- store-memory skill (global, for direct Qdrant storage bypassing cipher extraction) --
info "Setting up store-memory skill"
STORE_MEMORY_DIR="${HOME}/.claude/skills/store-memory"
if [ ! -d "$STORE_MEMORY_DIR" ]; then
  mkdir -p "$STORE_MEMORY_DIR"
  cat > "${STORE_MEMORY_DIR}/SKILL.md" <<'SKILLEOF'
---
name: store-memory
description: Use when storing knowledge, documentation, specs, or structured content in vector memory, especially when cipher_extract_and_operate_memory returns extracted:0 or skipped content, or when ingesting files and documents into memory
---

# Store Memory

Direct vector memory storage that bypasses cipher's LLM extraction layer. Uses Claude as the extraction brain and the embedding model for vector generation.

## When to Use

- Cipher's `cipher_extract_and_operate_memory` returned `extracted: 0`
- Storing documentation, specs, architecture decisions
- Bulk document ingestion (files from `docs/`, specs, etc.)
- Structured content with markdown, tables, code blocks
- Content longer than ~500 characters

## When NOT to Use

- Short conversational facts — cipher handles these fine
- Content that cipher successfully extracted

## Workflow

1. **Analyze**: What's worth storing? Break into independently-searchable chunks (~200-500 chars each).
2. **Dedup**: For each chunk, search Qdrant (threshold 0.85). Skip if similar exists.
3. **Store**: Embed via vllm-mlx, write to Qdrant with cipher-compatible payload.
4. **Verify**: Search for a stored entry to confirm retrieval works.

## Code Pattern

Use `ctx_execute` with JavaScript, requiring the shared helper:

```javascript
const { storeWithDedup, search } = require(process.env.HOME + '/.local/lib/qdrant-store.js');
const result = await storeWithDedup('knowledge_memory', text, ['tag1', 'tag2'], {
  domain: 'iOS', projectId: 'acme-ios', source: 'docs/kb'
});
console.log(JSON.stringify(result));
```

## Payload Schema (cipher-compatible)

| Field | Type | Notes |
|-------|------|-------|
| text | string | **Required** — searchable content |
| tags | string[] | Searchable tags |
| timestamp | ISO string | Auto-set by helper |
| source | string | e.g. "docs/kb", "session-insight" |
| domain | string | e.g. "iOS", "devops" |
| confidence | float | 0.95 default |
| event | string | "ADD" |
| projectId | string | e.g. "acme-ios" |

## Collections

| Collection | Use for |
|------------|---------|
| knowledge_memory | Facts, patterns, decisions, specs |
| workspace_memory | Team progress, bugs, project context |
| reflection_memory | Reasoning traces (use cipher_store_reasoning_memory) |

## Chunking Guidelines

- Each chunk: independently searchable, ~200-500 chars
- Include key identifiers (class names, ticket numbers, file paths)
- Don't split tightly-related context across chunks

## Common Mistakes

- **Storing raw file contents** — summarize and extract key facts instead
- **One giant entry** — break into chunks for better search precision
- **Missing `encoding_format: 'float'`** — causes 192-dim zeros (the fix-openai-embeddings.js preload handles this for cipher, but direct HTTP calls need it explicit)
- **Not verifying** — always search after storing to confirm retrieval
SKILLEOF
  info "store-memory → ${STORE_MEMORY_DIR}"
else
  info "store-memory already in place"
fi

# ── 8. Context Tree ─────────────────────────────────────
lane "Planting the knowledge tree 🌳"
mkdir -p "${PWD}/${XGH_CONTEXT_TREE}"

if [ ! -f "${PWD}/${XGH_CONTEXT_TREE}/_manifest.json" ]; then
  cat > "${PWD}/${XGH_CONTEXT_TREE}/_manifest.json" <<MANIFESTEOF
{
  "version": 1,
  "team": "${XGH_TEAM}",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "entries": []
}
MANIFESTEOF
fi

# ── 9. Gitignore ─────────────────────────────────────────
info "Updating .gitignore"
GITIGNORE="${PWD}/.gitignore"
touch "$GITIGNORE"
for pattern in ".xgh/local/" "data/cipher-sessions.db*" ".claude/settings.local.json" ".mcp.json"; do
  grep -qxF "$pattern" "$GITIGNORE" 2>/dev/null || echo "$pattern" >> "$GITIGNORE"
done

# ── 10. CLAUDE.local.md ─────────────────────────────────
info "Injecting xgh instructions into CLAUDE.local.md"
CLAUDE_MD="${PWD}/CLAUDE.local.md"
if ! grep -q "mcs:begin xgh" "$CLAUDE_MD" 2>/dev/null; then
  TEMPLATE="${PACK_DIR}/templates/instructions.md"
  if [ -f "$TEMPLATE" ]; then
    {
      echo ""
      echo "<!-- mcs:begin xgh.instructions -->"
      sed "s/__TEAM_NAME__/${XGH_TEAM}/g; s|__CONTEXT_TREE_PATH__|${XGH_CONTEXT_TREE}|g" "$TEMPLATE"
      echo "<!-- mcs:end xgh.instructions -->"
    } >> "$CLAUDE_MD"
  else
    cat >> "$CLAUDE_MD" <<CLAUDEEOF

<!-- mcs:begin xgh.instructions -->
# xgh (extreme-go-horsebot) — Self-Learning Memory
Team: ${XGH_TEAM} | Context Tree: ${XGH_CONTEXT_TREE}/
<!-- mcs:end xgh.instructions -->
CLAUDEEOF
  fi
fi

# ── 11. Optional Plugins ──────────────────────────────────
XGH_INSTALL_PLUGINS="${XGH_INSTALL_PLUGINS:-ask}"

install_plugin() {
  local marketplace="$1" plugin="$2" label="$3"
  if command -v claude &>/dev/null; then
    info "${label}"
    claude plugin marketplace add "$marketplace" &>/dev/null || true
    claude plugin install "${plugin}" &>/dev/null || {
      warn "Could not install ${label} — you can install it manually later"
      return 1
    }
    info "${label} ✓"
  else
    warn "Claude CLI not found — install ${label} manually:"
    echo "    claude plugin marketplace add ${marketplace}"
    echo "    claude plugin install ${plugin}"
  fi
}

if [ "$XGH_DRY_RUN" -eq 0 ] && [ "$XGH_INSTALL_PLUGINS" != "skip" ]; then
  lane "Optional superpowers 🦸"

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

  # ── superpowers ─────────────────────────────────────────
  INSTALL_SUPERPOWERS="n"
  if [ "$XGH_INSTALL_PLUGINS" = "all" ]; then
    INSTALL_SUPERPOWERS="y"
  elif [ "$XGH_INSTALL_PLUGINS" = "ask" ]; then
    echo ""
    echo -e "  ${BOLD}superpowers${NC} ${DIM}by obra${NC}"
    echo -e "  ${DIM}TDD, brainstorming, plan writing, subagent dev, code review${NC}"
    echo ""
    read -r -p "  🤖 Install? [y/N] " INSTALL_SUPERPOWERS
  fi
  if [[ "$(printf '%s' "$INSTALL_SUPERPOWERS" | tr '[:upper:]' '[:lower:]')" =~ ^y ]]; then
    install_plugin "obra/superpowers-marketplace" "superpowers@superpowers-marketplace" "superpowers"
  fi
fi

# ── 11b. Claude Code MCP Detection ────────────────────────
# Detect what MCPs are already connected in Claude Code (remote or local).
# Skills use this at runtime to know what's available vs. needs setup.

if command -v claude &>/dev/null && [ "$XGH_DRY_RUN" -eq 0 ]; then
  lane "Detecting connected MCPs 🔌"

  # Parse `claude mcp list` for all connected servers
  CONNECTED_MCPS=""
  while IFS= read -r line; do
    if echo "$line" | grep -q "✓ Connected"; then
      name=$(echo "$line" | sed 's/:.*//' | xargs)
      CONNECTED_MCPS="${CONNECTED_MCPS}${name},"
      info "${name} ✓"
    fi
  done < <(claude mcp list 2>/dev/null)

  if [ -z "$CONNECTED_MCPS" ]; then
    info "No MCPs detected (besides Cipher)"
  fi

  # Save state for skills to read at runtime
  CONNECTOR_STATE="${PWD}/.xgh/connectors.json"
  mkdir -p "$(dirname "$CONNECTOR_STATE")"
  cat > "$CONNECTOR_STATE" <<CONNEOF
{
  "detected_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "connected": [$(echo "$CONNECTED_MCPS" | sed 's/,$//' | sed 's/\([^,]*\)/"\1"/g' | sed 's/,/, /g')],
  "community_mcps": [
    {"name": "Slack", "package": "@anthropic/mcp-slack", "env": ["SLACK_BOT_TOKEN"]},
    {"name": "Linear", "package": "@anthropic/mcp-linear", "env": ["LINEAR_API_KEY"]},
    {"name": "Atlassian", "package": "@anthropic/mcp-atlassian", "env": ["ATLASSIAN_API_TOKEN", "ATLASSIAN_SITE_URL", "ATLASSIAN_EMAIL"]},
    {"name": "Figma", "package": "@anthropic/mcp-figma", "env": ["FIGMA_ACCESS_TOKEN"]},
    {"name": "Asana", "package": "@anthropic/mcp-asana", "env": ["ASANA_ACCESS_TOKEN"]},
    {"name": "Shortcut", "package": "@anthropic/mcp-shortcut", "env": ["SHORTCUT_API_TOKEN"]}
  ]
}
CONNEOF
  info "MCP state → ${CONNECTOR_STATE}"
else
  info "Skipping MCP detection (dry run or no claude CLI)"
fi

# ── 12. Model config ─────────────────────────────────────
info "Writing model configuration to ~/.xgh/models.env"
mkdir -p "$HOME/.xgh"
cat > "$HOME/.xgh/models.env" <<MODELSEOF
# xgh model server configuration — generated by installer
XGH_LLM_MODEL="${XGH_LLM_MODEL}"
XGH_EMBED_MODEL="${XGH_EMBED_MODEL}"
XGH_MODEL_PORT="${XGH_MODEL_PORT}"
MODELSEOF
# Note: vllm-mlx model server runs as a launchd/systemd daemon (see ingest-schedule.sh)

# ── xgh-ingest setup ──────────────────────────────────────
if [ "$XGH_DRY_RUN" -eq 0 ]; then
  lane "Setting up the ingest pipeline 📡"

  mkdir -p "$HOME/.xgh/inbox/processed"
  mkdir -p "$HOME/.xgh/logs"
  mkdir -p "$HOME/.xgh/digests"
  mkdir -p "$HOME/.xgh/calibration"
  mkdir -p "$HOME/.xgh/lib"
  mkdir -p "$HOME/.xgh/schedulers"

  # Copy lib helpers
  cp "${PACK_DIR}/lib/workspace-write.js"  "$HOME/.xgh/lib/"
  cp "${PACK_DIR}/lib/config-reader.sh"    "$HOME/.xgh/lib/"
  cp "${PACK_DIR}/lib/usage-tracker.sh"    "$HOME/.xgh/lib/"
  chmod +x "$HOME/.xgh/lib/config-reader.sh" "$HOME/.xgh/lib/usage-tracker.sh"

  # Copy config template only if ~/.xgh/ingest.yaml doesn't exist yet
  if [ ! -f "$HOME/.xgh/ingest.yaml" ]; then
    cp "${PACK_DIR}/config/ingest-template.yaml" "$HOME/.xgh/ingest.yaml"
    info "Created ~/.xgh/ingest.yaml — edit your profile, then run /xgh-track to add projects"
  fi

  # Copy scheduler templates
  cp "${PACK_DIR}/scripts/schedulers/com.xgh.retriever.plist" "$HOME/.xgh/schedulers/"
  cp "${PACK_DIR}/scripts/schedulers/com.xgh.analyzer.plist"  "$HOME/.xgh/schedulers/"
  cp "${PACK_DIR}/scripts/schedulers/com.xgh.models.plist"    "$HOME/.xgh/schedulers/"
  cp "${PACK_DIR}/scripts/ingest-schedule.sh" "$HOME/.xgh/lib/"
  chmod +x "$HOME/.xgh/lib/ingest-schedule.sh"

  # Auto-install the scheduler
  if [ "$XGH_DRY_RUN" -eq 0 ]; then
    bash "$HOME/.xgh/lib/ingest-schedule.sh" install || warn "Could not install scheduler — run ~/.xgh/lib/ingest-schedule.sh install manually"
  else
    info "Dry run — skipping scheduler install"
  fi
  info "Run /xgh-doctor to validate the pipeline"
fi

# ── Claude CLI auth check ────────────────────────────────
if command -v claude &>/dev/null; then
  if AUTH_JSON=$(claude auth status 2>/dev/null) && echo "$AUTH_JSON" | grep -q '"loggedIn": true'; then
    AUTH_EMAIL=$(echo "$AUTH_JSON" | grep '"email"' | sed 's/.*"email": *"//;s/".*//')
    info "Claude CLI authenticated${AUTH_EMAIL:+ as ${AUTH_EMAIL}}"
  else
    warn "Claude CLI found but not authenticated"
    warn "Run ${BOLD}claude${NC} to complete login before using xgh"
  fi
else
  warn "Claude CLI not found — install it, then run ${BOLD}claude${NC} to log in"
fi

# ── Done ─────────────────────────────────────────────────
echo ""
echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}🐴🤖 xgh is ready to ride!${NC}"
echo ""
echo -e "  ${DIM}Team${NC}         ${XGH_TEAM}"
echo -e "  ${DIM}Preset${NC}       ${XGH_PRESET}"
echo -e "  ${DIM}LLM${NC}          ${XGH_LLM_MODEL}"
echo -e "  ${DIM}Embeddings${NC}   ${XGH_EMBED_MODEL}"
echo -e "  ${DIM}Context tree${NC} ${XGH_CONTEXT_TREE}/"
echo -e "  ${DIM}Scope${NC}        ${XGH_HOOKS_SCOPE}"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo ""
echo -e "  ${GREEN}1.${NC} Launch Claude    ${DIM}claude${NC}"
echo -e "  ${GREEN}2.${NC} Run briefing     ${DIM}/xgh-brief${NC}"
echo -e ""
echo -e "  ${DIM}Models run automatically as a daemon (launchd/systemd).${NC}"
echo ""
echo -e "  ${DIM}Your AI now remembers. Ship it. 🐴${NC}"
echo ""
echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
