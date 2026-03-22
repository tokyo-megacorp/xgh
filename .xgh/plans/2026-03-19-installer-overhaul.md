# Installer Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make both xgh and lossless-claude installers self-sufficient with comprehensive verification, eliminating silent failures.

**Architecture:** lossless-claude owns the memory stack (daemon, cipher, Qdrant, MCP servers, hooks). xgh owns the workflow layer (skills, context tree, ingest). Each installer ends with a verify-and-fix step. `lossless-claude doctor` is the central diagnostic command.

**Tech Stack:** TypeScript (lossless-claude), Bash (xgh install.sh, setup.sh), Vitest (lossless-claude tests), Bash assertions (xgh tests)

**Spec:** `.xgh/specs/2026-03-19-installer-overhaul-design.md`

---

## Part A: lossless-claude changes (`/Users/pedro/Developer/lossless-claude/`)

### Task A1: Add `--version` and `status` commands to CLI

**Files:**
- Modify: `bin/lossless-claude.ts`
- Test: `test/cli.test.ts` (create)

- [x] **Step 1: Write failing tests**

Create `test/cli.test.ts`:

```typescript
import { describe, it, expect } from "vitest";
import { spawnSync } from "node:child_process";

const CLI = "./dist/bin/lossless-claude.js";

describe("CLI commands", () => {
  it("--version prints version from package.json", () => {
    const result = spawnSync("node", [CLI, "--version"], { encoding: "utf-8" });
    expect(result.stdout.trim()).toMatch(/^\d+\.\d+\.\d+$/);
    expect(result.status).toBe(0);
  });

  it("-v is alias for --version", () => {
    const result = spawnSync("node", [CLI, "-v"], { encoding: "utf-8" });
    expect(result.stdout.trim()).toMatch(/^\d+\.\d+\.\d+$/);
  });

  it("status prints one-line summary", () => {
    const result = spawnSync("node", [CLI, "status"], { encoding: "utf-8" });
    // Should contain daemon status even if not running
    expect(result.stdout).toContain("daemon:");
    expect(result.status).toBe(0);
  });
});
```

- [x] **Step 2: Run tests to verify they fail**

Run: `cd /Users/pedro/Developer/lossless-claude && npm run build && npx vitest run test/cli.test.ts`
Expected: FAIL — no --version or status case in switch

- [x] **Step 3: Implement --version and status in CLI**

Add to `bin/lossless-claude.ts` before the switch statement:

```typescript
if (command === "--version" || command === "-v") {
  const { readFileSync } = await import("node:fs");
  const { join, dirname } = await import("node:path");
  const { fileURLToPath } = await import("node:url");
  const pkgPath = join(dirname(fileURLToPath(import.meta.url)), "..", "package.json");
  const pkg = JSON.parse(readFileSync(pkgPath, "utf-8"));
  stdout.write(pkg.version + "\n");
  exit(0);
}
```

Add `status` case to the switch:

```typescript
case "status": {
  const { loadDaemonConfig } = await import("../src/daemon/config.js");
  const { join } = await import("node:path");
  const { homedir } = await import("node:os");
  const config = loadDaemonConfig(join(homedir(), ".lossless-claude", "config.json"));
  const port = config.port ?? 3737;

  let daemonStatus = "down";
  try {
    const res = await fetch(`http://localhost:${port}/health`);
    if (res.ok) daemonStatus = "up";
  } catch {}

  let qdrantStatus = "down";
  try {
    const res = await fetch("http://localhost:6333/healthz");
    if (res.ok) qdrantStatus = "up";
  } catch {}

  console.log(`daemon: ${daemonStatus} · qdrant: ${qdrantStatus} · provider: ${config.llm?.provider ?? "unknown"}`);
  break;
}
```

- [x] **Step 4: Build and run tests**

Run: `cd /Users/pedro/Developer/lossless-claude && npm run build && npx vitest run test/cli.test.ts`
Expected: PASS

- [x] **Step 5: Commit**

```bash
cd /Users/pedro/Developer/lossless-claude
git add bin/lossless-claude.ts test/cli.test.ts
git commit -m "feat: add --version and status commands to CLI"
```

---

### Task A2: Add cipher installation to `lossless-claude install`

**Files:**
- Modify: `installer/install.ts`
- Create: `installer/templates/cipher-mcp.js`
- Create: `installer/templates/fix-openai-embeddings.js`
- Test: `test/installer/install.test.ts` (modify)

- [x] **Step 1: Create cipher-mcp wrapper template**

Create `installer/templates/cipher-mcp.js` — this is the wrapper that filters cipher's stray stdout and injects the OpenAI SDK fix:

```javascript
#!/usr/bin/env node
// Wrapper for cipher MCP — filters non-JSON stdout, injects embedding fix
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

process.stdin.pipe(child.stdin);

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
```

- [x] **Step 2: Create fix-openai-embeddings.js template**

Create `installer/templates/fix-openai-embeddings.js` — copy the existing file from `~/.local/lib/fix-openai-embeddings.js`:

```bash
cp ~/.local/lib/fix-openai-embeddings.js /Users/pedro/Developer/lossless-claude/installer/templates/fix-openai-embeddings.js
```

- [x] **Step 3: Write failing tests for cipher setup**

Add to `test/installer/install.test.ts`:

```typescript
describe("cipher setup", () => {
  it("installs cipher npm package if missing", () => {
    // Mock spawnSync to track npm install calls
    const calls: string[][] = [];
    const deps = makeDeps({
      spawnSync: (cmd: string, args: string[]) => {
        calls.push([cmd, ...args]);
        if (cmd === "sh" && args[1]?.includes("command -v cipher"))
          return { status: 1, stdout: "", stderr: "" }; // cipher not found
        return { status: 0, stdout: "", stderr: "" };
      }
    });
    // installCipher should call npm install -g @byterover/cipher
    installCipher(deps);
    expect(calls.some(c => c.includes("@byterover/cipher"))).toBe(true);
  });

  it("creates cipher-mcp wrapper", () => {
    const written: Record<string, string> = {};
    const deps = makeDeps({
      writeFileSync: (path: string, content: string) => { written[path] = content; }
    });
    installCipher(deps);
    const wrapperPath = Object.keys(written).find(p => p.includes("cipher-mcp"));
    expect(wrapperPath).toBeDefined();
  });

  it("registers cipher MCP in settings.json", () => {
    const settings = { mcpServers: {}, hooks: {} };
    const result = mergeCipherSettings(settings, {
      embeddingModel: "test-model",
      embeddingBaseURL: "http://localhost:11435/v1",
      llmModel: "test-llm",
      llmBaseURL: "http://localhost:11435/v1",
      backend: "vllm-mlx"
    });
    expect(result.mcpServers.cipher).toBeDefined();
    expect(result.mcpServers.cipher.env.EMBEDDING_MODEL).toBe("test-model");
  });
});
```

- [x] **Step 4: Run tests to verify they fail**

Run: `cd /Users/pedro/Developer/lossless-claude && npm run build && npx vitest run test/installer/install.test.ts`
Expected: FAIL — installCipher and mergeCipherSettings don't exist

- [x] **Step 5: Implement cipher setup in install.ts**

Add these exported functions to `installer/install.ts`:

1. `installCipherPackage(deps)` — runs `npm install -g @byterover/cipher` if `cipher` not in PATH
2. `installCipherWrapper(deps)` — copies `cipher-mcp.js` template to `~/.local/bin/cipher-mcp`, makes executable
3. `installCipherSdkFix(deps)` — copies `fix-openai-embeddings.js` template to `~/.local/lib/`
4. `mergeCipherSettings(existing, cipherConfig)` — adds cipher MCP entry to settings.json with env vars derived from cipher.yml
5. `parseCipherConfig(cipherYmlPath, deps)` — reads cipher.yml and extracts model/URL/provider info

Update `install()` to call these after setup.sh and before settings merge.

- [x] **Step 6: Update build script to copy templates**

Modify `package.json` scripts.build:

```json
"build": "tsc && cp installer/setup.sh dist/installer/setup.sh && cp -r installer/templates dist/installer/templates"
```

- [x] **Step 7: Build and run all installer tests**

Run: `cd /Users/pedro/Developer/lossless-claude && npm run build && npx vitest run test/installer/`
Expected: PASS

- [x] **Step 8: Commit**

```bash
cd /Users/pedro/Developer/lossless-claude
git add installer/install.ts installer/templates/ package.json test/installer/
git commit -m "feat: install cipher MCP during lossless-claude install"
```

---

### Task A3: Add claude-max-api-proxy installation

**Files:**
- Modify: `installer/install.ts`
- Test: `test/installer/install.test.ts` (modify)

- [x] **Step 1: Write failing test**

Add to `test/installer/install.test.ts`:

```typescript
describe("claude-max-api-proxy setup", () => {
  it("installs when summarizer is claude-cli and binary missing", () => {
    const calls: string[][] = [];
    const deps = makeDeps({
      spawnSync: (cmd: string, args: string[]) => {
        calls.push([cmd, ...args]);
        if (args[1]?.includes("command -v claude-server") || args[1]?.includes("command -v claude-max-api"))
          return { status: 1, stdout: "", stderr: "" };
        return { status: 0, stdout: "", stderr: "" };
      }
    });
    installClaudeServer(deps, { provider: "claude-cli" });
    expect(calls.some(c => c.includes("claude-max-api-proxy"))).toBe(true);
  });

  it("skips when summarizer is not claude-cli", () => {
    const calls: string[][] = [];
    const deps = makeDeps({
      spawnSync: (cmd: string, args: string[]) => {
        calls.push([cmd, ...args]);
        return { status: 0, stdout: "", stderr: "" };
      }
    });
    installClaudeServer(deps, { provider: "anthropic" });
    expect(calls.some(c => c.includes("claude-max-api-proxy"))).toBe(false);
  });
});
```

- [x] **Step 2: Run test — expect FAIL**

Run: `cd /Users/pedro/Developer/lossless-claude && npm run build && npx vitest run test/installer/install.test.ts`

- [x] **Step 3: Implement installClaudeServer**

Add to `installer/install.ts`:

```typescript
export function installClaudeServer(deps = defaultDeps, config: { provider: string }) {
  if (config.provider !== "claude-cli") return;

  // Check if claude-server or claude-max-api exists
  const hasServer = deps.spawnSync("sh", ["-c", "command -v claude-server || command -v claude-max-api"], { encoding: "utf-8" });
  if (hasServer.status === 0) return;

  console.log("Installing claude-max-api-proxy (Claude Max summarizer)...");
  const result = deps.spawnSync("npm", ["install", "-g", "claude-max-api-proxy"], { stdio: "inherit" });
  if (result.status !== 0) {
    console.warn("Warning: Could not install claude-max-api-proxy — summarization via Claude CLI may not work");
  }
}
```

Wire into `install()` function after config.json creation.

- [x] **Step 4: Build and test**

Run: `cd /Users/pedro/Developer/lossless-claude && npm run build && npx vitest run test/installer/install.test.ts`
Expected: PASS

- [x] **Step 5: Commit**

```bash
cd /Users/pedro/Developer/lossless-claude
git add installer/install.ts test/installer/install.test.ts
git commit -m "feat: install claude-max-api-proxy when summarizer is claude-cli"
```

---

### Task A4: Add health-wait after daemon and Qdrant start

**Files:**
- Modify: `installer/install.ts`
- Test: `test/installer/install.test.ts` (modify)

- [x] **Step 1: Write failing test**

```typescript
describe("health-wait", () => {
  it("polls daemon health until ready", async () => {
    let attempts = 0;
    const deps = makeDeps({
      fetch: async () => {
        attempts++;
        if (attempts < 3) throw new Error("not ready");
        return new Response("ok", { status: 200 });
      }
    });
    const ok = await waitForHealth("http://localhost:3737/health", 5000, deps);
    expect(ok).toBe(true);
    expect(attempts).toBe(3);
  });

  it("returns false after timeout", async () => {
    const deps = makeDeps({
      fetch: async () => { throw new Error("never ready"); }
    });
    const ok = await waitForHealth("http://localhost:3737/health", 500, deps);
    expect(ok).toBe(false);
  });
});
```

- [x] **Step 2: Run test — expect FAIL**

- [x] **Step 3: Implement waitForHealth**

Add to `installer/install.ts`:

```typescript
export async function waitForHealth(
  url: string,
  timeoutMs: number = 10000,
  deps: { fetch?: typeof globalThis.fetch } = {}
): Promise<boolean> {
  const fetchFn = deps.fetch ?? globalThis.fetch;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetchFn(url);
      if (res.ok) return true;
    } catch {}
    await new Promise(r => setTimeout(r, 500));
  }
  return false;
}
```

Wire into `install()` after `setupDaemonService()`:

```typescript
console.log("Waiting for daemon...");
const daemonOk = await waitForHealth(`http://localhost:${config.port ?? 3737}/health`);
if (!daemonOk) console.warn("Warning: daemon not responding — run: lossless-claude doctor");

console.log("Waiting for Qdrant...");
const qdrantOk = await waitForHealth("http://localhost:6333/healthz");
if (!qdrantOk) console.warn("Warning: Qdrant not responding — run: lossless-claude doctor");
```

- [x] **Step 4: Build and test**

Run: `cd /Users/pedro/Developer/lossless-claude && npm run build && npx vitest run test/installer/install.test.ts`
Expected: PASS

- [x] **Step 5: Commit**

```bash
cd /Users/pedro/Developer/lossless-claude
git add installer/install.ts test/installer/install.test.ts
git commit -m "feat: health-wait after daemon and Qdrant start during install"
```

---

### Task A5: Implement `lossless-claude doctor`

This is the largest task. The doctor command runs conditional checks and auto-fixes.

**Files:**
- Create: `src/doctor/doctor.ts`
- Create: `src/doctor/checks.ts`
- Create: `src/doctor/auto-fix.ts`
- Modify: `bin/lossless-claude.ts`
- Test: `test/doctor/doctor.test.ts` (create)

- [x] **Step 1: Define check interface and result types**

Create `src/doctor/checks.ts`:

```typescript
export interface CheckResult {
  name: string;
  status: "pass" | "warn" | "fail";
  message: string;
  fixApplied?: boolean;
}

export interface DoctorConfig {
  backend: "vllm-mlx" | "ollama" | "remote";
  summarizer: "claude-cli" | "anthropic" | "openai" | "disabled";
  daemonPort: number;
  qdrantUrl: string;
  remoteUrl?: string;
  modelPort: number;
  embeddingModel: string;
  llmModel: string;
}
```

- [x] **Step 2: Write failing tests for core checks**

Create `test/doctor/doctor.test.ts`:

```typescript
import { describe, it, expect } from "vitest";
import { runDoctor } from "../../src/doctor/doctor.js";

describe("doctor", () => {
  it("returns pass when everything is healthy", async () => {
    const results = await runDoctor({
      // mock all checks passing
    });
    expect(results.every(r => r.status === "pass")).toBe(true);
  });

  it("detects missing config.json", async () => {
    const results = await runDoctor({
      existsSync: (p: string) => !p.includes("config.json"),
    });
    const configCheck = results.find(r => r.name === "config");
    expect(configCheck?.status).toBe("fail");
  });

  it("auto-fixes missing hooks in settings.json", async () => {
    let settingsWritten = false;
    const results = await runDoctor({
      readFileSync: (p: string) => {
        if (p.includes("settings.json")) return '{"hooks":{},"mcpServers":{}}';
        if (p.includes("config.json")) return '{"port":3737,"llm":{"provider":"disabled"}}';
        throw new Error("not found");
      },
      writeFileSync: () => { settingsWritten = true; },
      existsSync: () => true,
    });
    const hookCheck = results.find(r => r.name === "hooks");
    expect(hookCheck?.fixApplied).toBe(true);
    expect(settingsWritten).toBe(true);
  });

  it("skips vllm-mlx checks when backend is ollama", async () => {
    const results = await runDoctor({
      backend: "ollama",
    });
    const vllmCheck = results.find(r => r.name === "vllm-mlx");
    expect(vllmCheck).toBeUndefined();
  });

  it("checks claude-server only when summarizer is claude-cli", async () => {
    const results = await runDoctor({
      summarizer: "anthropic",
    });
    const csCheck = results.find(r => r.name === "claude-server");
    expect(csCheck).toBeUndefined();
  });
});
```

- [x] **Step 3: Run tests — expect FAIL**

Run: `cd /Users/pedro/Developer/lossless-claude && npm run build && npx vitest run test/doctor/`

- [x] **Step 4: Implement doctor module**

Create `src/doctor/doctor.ts` with `runDoctor()` function that runs all checks in order:

1. Binary version (read package.json)
2. config.json exists (auto-fix: create defaults)
3. cipher.yml exists
4. Qdrant health — conditional on backend (auto-fix: start service)
5. Backend-specific checks (vllm-mlx port / ollama port / remote URL)
6. Embedding endpoint check (conditional)
7. LLM endpoint check (conditional)
8. Daemon health (auto-fix: restart service)
9. Daemon service registered (auto-fix: re-create plist/unit + load)
10. settings.json hooks (auto-fix: merge)
11. settings.json MCP entries (auto-fix: merge)
12. cipher binary exists (auto-fix: npm install)
13. cipher-mcp wrapper exists (auto-fix: re-create)
14. cipher MCP in settings.json (auto-fix: merge)
15. Summarizer checks — conditional on provider
16. MCP handshake: lossless-claude (auto-fix: restart)
17. MCP handshake: cipher
18. Round-trip: store → search

Create `src/doctor/auto-fix.ts` with fix functions:
- `fixDaemonService()` — re-create plist/unit, load
- `fixSettings()` — merge missing hooks/MCP entries
- `fixCipherWrapper()` — re-create from template
- `restartDaemon()` — unload + load plist, or systemctl restart

- [x] **Step 5: Wire doctor into CLI**

Add to `bin/lossless-claude.ts` switch:

```typescript
case "doctor": {
  const { runDoctor, printResults } = await import("../src/doctor/doctor.js");
  const results = await runDoctor();
  printResults(results);
  const failures = results.filter(r => r.status === "fail");
  exit(failures.length > 0 ? 1 : 0);
}
```

- [x] **Step 6: Build and run all tests**

Run: `cd /Users/pedro/Developer/lossless-claude && npm run build && npx vitest run`
Expected: ALL PASS

- [x] **Step 7: Manual smoke test**

```bash
cd /Users/pedro/Developer/lossless-claude && npm run build
node dist/bin/lossless-claude.js doctor
```

Expected: Formatted output with check results for this machine.

- [x] **Step 8: Commit**

```bash
cd /Users/pedro/Developer/lossless-claude
git add src/doctor/ bin/lossless-claude.ts test/doctor/
git commit -m "feat: add lossless-claude doctor command with auto-fix"
```

---

### Task A6: Wire doctor into install, run doctor at end

**Files:**
- Modify: `installer/install.ts`

- [x] **Step 1: Import and call doctor at end of install()**

At the end of the `install()` function, after all setup steps:

```typescript
// Final verification
console.log("\nRunning doctor...");
const { runDoctor, printResults } = await import("../src/doctor/doctor.js");
const results = await runDoctor();
printResults(results);
const failures = results.filter(r => r.status === "fail");
if (failures.length > 0) {
  console.error(`\n${failures.length} check(s) failed. Run 'lossless-claude doctor' for details.`);
} else {
  console.log("\nlossless-claude installed successfully! All checks passed.");
}
```

- [x] **Step 2: Build and test**

Run: `cd /Users/pedro/Developer/lossless-claude && npm run build && npx vitest run`
Expected: PASS

- [x] **Step 3: Commit**

```bash
cd /Users/pedro/Developer/lossless-claude
git add installer/install.ts
git commit -m "feat: run doctor at end of install for verification"
```

---

### Task A7: Update build and publish

**Files:**
- Modify: `package.json`

- [x] **Step 1: Ensure templates are in `files` array**

The `files` field already includes `dist/`. Since templates are copied to `dist/installer/templates/` during build, they're already included. Verify:

```bash
cd /Users/pedro/Developer/lossless-claude && npm run build && ls dist/installer/templates/
```

Expected: `cipher-mcp.js`, `fix-openai-embeddings.js`

- [x] **Step 2: Run full test suite**

```bash
cd /Users/pedro/Developer/lossless-claude && npm run build && npm test
```

Expected: ALL PASS

- [x] **Step 3: Commit and tag**

```bash
cd /Users/pedro/Developer/lossless-claude
git add package.json
git commit -m "chore: ensure templates included in build"
```

---

## Part B: xgh changes (`/Users/pedro/Developer/xgh/`)

### Task B1: Delete dead artifacts from repo

**Files:**
- Delete: `scripts/schedulers/com.xgh.models.plist`

- [x] **Step 1: Delete the file**

```bash
rm /Users/pedro/Developer/xgh/scripts/schedulers/com.xgh.models.plist
```

- [x] **Step 2: Check if scripts/schedulers/ is now empty, remove if so**

```bash
rmdir /Users/pedro/Developer/xgh/scripts/schedulers/ 2>/dev/null || true
```

- [x] **Step 3: Run existing tests to ensure nothing breaks**

```bash
cd /Users/pedro/Developer/xgh && bash tests/test-install.sh
```

Expected: PASS (nothing references this file in tests)

- [x] **Step 4: Commit**

```bash
cd /Users/pedro/Developer/xgh
git add -A scripts/schedulers/
git commit -m "chore: delete dead models.plist (unresolved placeholders, never registered)"
```

---

### Task B2: Add migration cleanup to install.sh

**Files:**
- Modify: `install.sh`

- [x] **Step 1: Add migration block after legacy scheduler unload (after the `ingest-schedule.sh` block)**

Find the block that starts with `# ── Migrate: unload any previously installed OS-level scheduler` and add after it:

```bash
# ── Migrate: clean up orphaned artifacts from pre-March-2026 installs ──────
if [ -d "$HOME/.xgh/schedulers" ]; then
  rm -rf "$HOME/.xgh/schedulers"
  info "Removed orphaned ~/.xgh/schedulers/ (replaced by lossless-claude daemon)"
fi
if [ -f "$HOME/.xgh/models.env" ]; then
  rm -f "$HOME/.xgh/models.env"
  info "Removed legacy ~/.xgh/models.env (cipher.yml is source of truth)"
fi
```

- [x] **Step 2: Run install test**

```bash
cd /Users/pedro/Developer/xgh && bash tests/test-install.sh
```

Expected: PASS

- [x] **Step 3: Commit**

```bash
cd /Users/pedro/Developer/xgh
git add install.sh
git commit -m "fix: clean orphaned schedulers/ and models.env during migration"
```

---

### Task B3: Remove dead code from install.sh

**Files:**
- Modify: `install.sh`

- [x] **Step 1: Remove models.env creation block**

Remove the entire block:
```
# ── 12. Model config ─────────────────────────────────────
info "Writing model configuration to ~/.xgh/models.env"
mkdir -p "$HOME/.xgh"

XGH_MODEL_HOST="${XGH_MODEL_HOST:-127.0.0.1}"

cat > "$HOME/.xgh/models.env" <<MODELSEOF
...
MODELSEOF
# Note: model/backend setup is handled by lossless-claude install
```

- [x] **Step 2: Remove models.plist copy and schedulers mkdir**

Remove from the ingest setup section:
```
mkdir -p "$HOME/.xgh/schedulers"
```

And remove:
```
# Copy models plist and substitute XGH_MODEL_HOST placeholder
sed "s/127\.0\.0\.1/${XGH_MODEL_HOST}/g" \
  "${PACK_DIR}/scripts/schedulers/com.xgh.models.plist" \
  > "$HOME/.xgh/schedulers/com.xgh.models.plist"
```

- [x] **Step 3: Remove Homebrew install from xgh (let lossless-claude handle it)**

In the Dependencies section, remove:
```
if ! command -v brew &>/dev/null; then
  info "Homebrew not found — installing"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
```

Keep the node and python3 checks.

- [x] **Step 4: Run install test**

```bash
cd /Users/pedro/Developer/xgh && bash tests/test-install.sh
```

Expected: PASS (update test if any assertions check removed code)

- [x] **Step 5: Commit**

```bash
cd /Users/pedro/Developer/xgh
git add install.sh
git commit -m "fix: remove dead code (models.env, models.plist, brew install)"
```

---

### Task B4: Add .lossless-claude/ to .gitignore

**Files:**
- Modify: `install.sh`

- [x] **Step 1: Add pattern to gitignore loop**

Change the `for pattern in` line:

```bash
for pattern in ".xgh/local/" "data/cipher-sessions.db*" ".claude/settings.local.json" ".mcp.json" ".lossless-claude/"; do
```

- [x] **Step 2: Run install test**

```bash
cd /Users/pedro/Developer/xgh && bash tests/test-install.sh
```

- [x] **Step 3: Commit**

```bash
cd /Users/pedro/Developer/xgh
git add install.sh
git commit -m "fix: add .lossless-claude/ to .gitignore template"
```

---

### Task B5: Improve lossless-claude install error handling

**Files:**
- Modify: `install.sh`

- [x] **Step 1: Replace generic warning with doctor-based diagnostics**

Replace the current lossless-claude install block:

```bash
if command -v lossless-claude &>/dev/null; then
  lossless-claude install || warn "lossless-claude install failed — run manually: lossless-claude install"
else
  info "Skipping lossless-claude setup — memory features unavailable until installed"
fi
```

With:

```bash
if command -v lossless-claude &>/dev/null; then
  lossless-claude install || {
    warn "lossless-claude install had issues — running doctor..."
    lossless-claude doctor || warn "Some checks failed — run 'lossless-claude doctor' after fixing"
  }
else
  info "Skipping lossless-claude setup — memory features unavailable until installed"
fi
```

- [x] **Step 2: Run install test**

```bash
cd /Users/pedro/Developer/xgh && bash tests/test-install.sh
```

- [x] **Step 3: Commit**

```bash
cd /Users/pedro/Developer/xgh
git add install.sh
git commit -m "fix: run lossless-claude doctor on install failure for diagnostics"
```

---

### Task B6: Add post-install validation to install.sh

**Files:**
- Modify: `install.sh`

- [x] **Step 1: Add validation function before the Done banner**

Insert before `# ── Done ─────`:

```bash
# ── Post-install validation ──────────────────────────────
if [ "$XGH_DRY_RUN" -eq 0 ]; then
  lane "Post-install validation 🔍"

  _V_PASS=0
  _V_FAIL=0
  _V_WARN=0

  _check_pass() { _V_PASS=$((_V_PASS + 1)); info "✅ $1"; }
  _check_warn() { _V_WARN=$((_V_WARN + 1)); warn "⚠️  $1"; }
  _check_fail() { _V_FAIL=$((_V_FAIL + 1)); error "❌ $1"; }

  # 1. Memory stack
  if command -v lossless-claude &>/dev/null; then
    if lossless-claude doctor 2>/dev/null; then
      _check_pass "Memory stack (lossless-claude doctor)"
    else
      _check_fail "Memory stack — run: lossless-claude doctor"
    fi
  else
    _check_warn "lossless-claude not installed — memory features unavailable"
  fi

  # 2. Plugin registration
  PLUGINS_JSON="${HOME}/.claude/plugins/installed_plugins.json"
  if [ -f "$PLUGINS_JSON" ] && python3 -c "
import json, sys
d = json.load(open('${PLUGINS_JSON}'))
sys.exit(0 if 'xgh@extreme-go-horse' in d.get('plugins', {}) else 1)
" 2>/dev/null; then
    _check_pass "Plugin: xgh@extreme-go-horse registered"
  else
    _check_fail "Plugin not registered — re-run installer"
  fi

  # 3. Skills in cache
  SKILL_COUNT=$(find "${HOME}/.claude/plugins/cache/extreme-go-horse/xgh/" -name "*.md" -path "*/skills/*" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$SKILL_COUNT" -gt 0 ]; then
    _check_pass "Skills: ${SKILL_COUNT} skills in cache"
  else
    _check_fail "Skills missing from cache — re-run installer"
  fi

  # 4. Hooks in settings
  if [ -f "$SETTINGS_FILE" ] && python3 -c "
import json, sys
d = json.load(open('${SETTINGS_FILE}'))
hooks = d.get('hooks', {})
has_xgh = any('xgh-' in str(h) for event in hooks.values() for h in (event if isinstance(event, list) else []))
sys.exit(0 if has_xgh else 1)
" 2>/dev/null; then
    _check_pass "Hooks: xgh hooks registered"
  else
    _check_warn "xgh hooks may be missing — check settings.json"
  fi

  # 5. Context tree
  if [ -f "${PWD}/${XGH_CONTEXT_TREE}/_manifest.json" ]; then
    _check_pass "Context tree: ${XGH_CONTEXT_TREE}/_manifest.json"
  else
    _check_fail "Context tree missing"
  fi

  # 6. .gitignore
  if grep -q ".lossless-claude/" "$GITIGNORE" 2>/dev/null; then
    _check_pass "Gitignore: .lossless-claude/ ✓"
  else
    echo ".lossless-claude/" >> "$GITIGNORE"
    _check_warn "Added .lossless-claude/ to .gitignore"
  fi

  # 7. Ingest config
  if [ -f "$HOME/.xgh/ingest.yaml" ]; then
    _check_pass "Ingest config: ~/.xgh/ingest.yaml"
  else
    _check_warn "No ingest.yaml — run /xgh-track to configure"
  fi

  # 8. Claude CLI
  if command -v claude &>/dev/null; then
    if AUTH_JSON=$(claude auth status 2>/dev/null) && echo "$AUTH_JSON" | grep -q '"loggedIn": true'; then
      _check_pass "Claude CLI: authenticated"
    else
      _check_warn "Claude CLI: not authenticated — run: claude"
    fi
  else
    _check_warn "Claude CLI: not found — install it, then run: claude"
  fi

  echo ""
  info "${_V_PASS} passed, ${_V_FAIL} failed, ${_V_WARN} warnings"
fi
```

- [x] **Step 2: Remove the old standalone Claude CLI auth check (near end of file)**

Remove the block:
```bash
# ── Claude CLI auth check ────────────────────────────────
if command -v claude &>/dev/null; then
  ...
fi
```

Since it's now part of post-install validation.

- [x] **Step 3: Run install test**

```bash
cd /Users/pedro/Developer/xgh && bash tests/test-install.sh
```

- [x] **Step 4: Commit**

```bash
cd /Users/pedro/Developer/xgh
git add install.sh
git commit -m "feat: add post-install validation with auto-fix"
```

---

### Task B7: Update xgh tests for new behavior

**Files:**
- Modify: `tests/test-install.sh`

- [x] **Step 1: Remove assertions for deleted artifacts**

If any tests check for `models.env`, `schedulers/`, or `com.xgh.models.plist`, remove those assertions.

- [x] **Step 2: Add assertions for new behavior**

Add tests that verify:
- `.lossless-claude/` is in `.gitignore`
- No `models.env` is created
- No `schedulers/` directory is created
- Migration block cleans orphaned files (create them before running installer, verify they're gone after)

- [x] **Step 3: Run full test suite**

```bash
cd /Users/pedro/Developer/xgh && bash tests/test-install.sh && bash tests/test-config.sh && bash tests/test-uninstall.sh
```

Expected: ALL PASS

- [x] **Step 4: Commit**

```bash
cd /Users/pedro/Developer/xgh
git add tests/
git commit -m "test: update install tests for overhaul changes"
```

---

## Execution Order

Tasks can be parallelized across repos:

```
Parallel track 1 (lossless-claude):   A1 → A2 → A3 → A4 → A5 → A6 → A7
Parallel track 2 (xgh):               B1 → B2 → B3 → B4 → B5 → B6 → B7
```

B5 (doctor call in xgh) depends on A5 (doctor implementation), but can use a stub initially.

## Final Integration Test

After all tasks complete:

```bash
# 1. Build and install lossless-claude
cd /Users/pedro/Developer/lossless-claude && npm run build && npm install -g .

# 2. Verify doctor works
lossless-claude doctor

# 3. Run xgh installer (dry-run)
cd /Users/pedro/Developer/xgh && XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh

# 4. Run xgh tests
cd /Users/pedro/Developer/xgh && bash tests/test-install.sh

# 5. Full install test (non-dry-run, local pack)
cd /tmp/test-project && git init && XGH_LOCAL_PACK=/Users/pedro/Developer/xgh bash /Users/pedro/Developer/xgh/install.sh
```
