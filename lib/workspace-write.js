#!/usr/bin/env node
// lib/workspace-write.js — Write xgh ingest payloads to Cipher workspace collection
// Reads embedding config from ~/.cipher/cipher.yml to match Cipher's vector space
'use strict';

const fs = require('fs');
const path = require('path');
const { randomUUID } = require('crypto');

// Minimal YAML parser (avoids external deps) — handles the flat/nested structure of cipher.yml
function parseYaml(text) {
  const result = {};
  const stack = [{ obj: result, indent: -1 }];
  for (const raw of text.split('\n')) {
    // Only strip comments preceded by whitespace (preserves # in URLs, channel names, colors)
    const line = raw.replace(/\s+#(?!\S*:).*$/, '');
    const stripped = line.trimStart();
    if (!stripped) continue;
    const indent = line.length - stripped.length;
    const colon = stripped.indexOf(':');
    if (colon === -1) continue;
    const key = stripped.slice(0, colon).trim();
    let val = stripped.slice(colon + 1).trim().replace(/^['"]|['"]$/g, '');
    while (stack.length > 1 && stack[stack.length - 1].indent >= indent) stack.pop();
    const parent = stack[stack.length - 1].obj;
    if (!val) {
      parent[key] = {};
      stack.push({ obj: parent[key], indent });
    } else if (val === '{}') {
      parent[key] = {};
    } else if (val === '[]') {
      parent[key] = [];
    } else {
      parent[key] = val;
    }
  }
  return result;
}

function readYaml(filePath) {
  try { return parseYaml(fs.readFileSync(filePath, 'utf8')); }
  catch (err) {
    if (err.code !== 'ENOENT') console.warn(`Warning: failed to read ${filePath}: ${err.message}`);
    return {};
  }
}

// Parse CLI args
const args = process.argv.slice(2);
const opts = {};
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--text')     opts.text     = args[++i];
  else if (args[i] === '--type')    opts.type     = args[++i];
  else if (args[i] === '--project') opts.project  = args[++i];
  else if (args[i] === '--urgency') {
    const n = parseInt(args[++i], 10);
    if (isNaN(n)) { console.error('--urgency must be a number'); process.exit(1); }
    opts.urgency = n;
  }
  else if (args[i] === '--source')  opts.source   = args[++i];
  else if (args[i] === '--dry-run') opts.dryRun   = true;
}

if (!opts.text || !opts.type) {
  console.error('Usage: workspace-write.js --text "..." --type <type> [--project <p>] [--urgency <n>] [--source <s>] [--dry-run]');
  process.exit(1);
}

const home = process.env.HOME || require('os').homedir();
const cipherCfg = readYaml(path.join(home, '.cipher', 'cipher.yml'));
const xghCfg    = readYaml(path.join(home, '.xgh', 'ingest.yaml'));

const embeddingEndpoint = cipherCfg?.embedding?.baseURL || cipherCfg?.embedding?.endpoint || 'http://localhost:11434/v1';
const embeddingModel    = cipherCfg?.embedding?.model    || 'mlx-community/nomicai-modernbert-embed-base-8bit';
const qdrantUrl         = cipherCfg?.qdrant?.url         || 'http://localhost:6333';
const collection        = xghCfg?.cipher?.workspace_collection || 'xgh-workspace';

async function embed(text) {
  const res = await fetch(`${embeddingEndpoint}/embeddings`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: embeddingModel, input: text }),
  });
  if (!res.ok) throw new Error(`Embedding API ${res.status}: ${await res.text()}`);
  const data = await res.json();
  if (!data.data?.[0]?.embedding) throw new Error('Embedding API returned unexpected structure');
  return data.data[0].embedding;
}

async function main() {
  const payload = {
    text: opts.text,
    teamMember: xghCfg?.profile?.name || 'unknown',
    domain: String((xghCfg?.profile?.platforms || ['unknown'])[0] || xghCfg?.profile?.platforms || 'unknown'),
    project: opts.project || 'general',
    progressStatus: opts.type,
    bugs: [],
    workContext: {},
    xgh_content_type: opts.type,
    xgh_urgency_score: Math.min(opts.urgency || 0, 100),
    xgh_ttl: null,
    xgh_source: opts.source || 'unknown',
    xgh_timestamp: new Date().toISOString(),
    xgh_schema_version: 1,
    xgh_status: 'active',
  };

  if (opts.dryRun) {
    console.log('DRY RUN — would write:');
    console.log(JSON.stringify(payload, null, 2));
    return;
  }

  const vector = await embed(opts.text);
  const id = randomUUID();
  const res = await fetch(`${qdrantUrl}/collections/${collection}/points?wait=true`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ points: [{ id, vector, payload }] }),
  });
  if (!res.ok) throw new Error(`Qdrant ${res.status}: ${await res.text()}`);
  console.log(`✓ Written to ${collection}: ${id}`);
}

main().catch(err => { console.error('Error:', err.message); process.exit(1); });
