# Modular TUI Demo Engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the monolithic `claude-tui.html` with a data-driven TUI engine powered by YAML descriptors, and move the website into `src/site/` in the xgh repo.

**Architecture:** A build script reads shell config YAML + demo YAMLs + command YAMLs, converts them to JSON, and injects them into a generic engine.html template to produce a single output HTML file. The engine.html contains all CSS (parameterized via CSS custom properties) and JS (a generic scene player + command runner that operates on injected data). No bundler required.

**Tech Stack:** HTML/CSS/JS, YAML (PyYAML for build), Bash

**Spec:** `.xgh/specs/2026-03-22-modular-tui-demo-engine-design.md`

---

## File Structure

```
src/site/
  index.html                              # landing page (copied from extreme-go-horse.com)
  tui/
    engine.html                           # generic TUI template (CSS + JS engine, no data)
    build.sh                              # reads YAML → injects JSON → writes output
    shells/
      claude.yaml                         # Claude Code visual identity + theme
    demos/
      claude/
        1-briefing.yaml                   # scene 1: /xgh-brief
        2-codex-review.yaml               # scene 2: /xgh-codex review
        3-memory.yaml                     # scene 3: how does seed-global-config work?
    commands/
      install.yaml
      about.yaml
      color.yaml                          # handler: color
      rename.yaml                         # handler: rename
      help.yaml                           # handler: help
    out/
      claude-tui.html                     # generated output (committed for deploy)
```

---

### Task 1: Move website into xgh repo

**Files:**
- Create: `src/site/index.html` (copy from extreme-go-horse.com)
- Create: `src/site/tui/` (empty dir for now)

This task just migrates the landing page. The TUI will be rebuilt from scratch in later tasks.

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p src/site/tui/out
mkdir -p src/site/tui/shells
mkdir -p src/site/tui/demos/claude
mkdir -p src/site/tui/commands
```

- [ ] **Step 2: Copy landing page**

```bash
cp /Users/pedro/Developer/extreme-go-horse.com/index.html src/site/index.html
```

- [ ] **Step 3: Commit**

```bash
git add src/site/index.html
git commit -m "chore: move landing page into src/site/"
```

---

### Task 2: Write shell config (`shells/claude.yaml`)

**Files:**
- Create: `src/site/tui/shells/claude.yaml`

Extract all hardcoded values from the current `claude-tui.html` into the shell config.

- [ ] **Step 1: Create the shell config file**

```yaml
name: claude
title: "Claude Code"
version: "v2.1.81"

path:
  text: "x.com/ipedro"
  url: "https://x.com/ipedro"

prompt: "›"

titlebar:
  text: "extreme-go-horse"
  detail: "— bun • claude --dangerously-skip-permissions — 102×31"

models:
  - "Sonnet 4.6 with medium effort · Claude Max"
  - "Sonnet 4.6 with high effort · Claude Max"
  - "Opus 4.6 with medium effort · Claude Max"
  - "Opus 4.6 · Claude Max"
  - "Haiku 4.5 · Claude Max"
  - "Sonnet 4.6 · Claude Pro"

theme:
  bg: "#0d0e17"
  window: "#1a1b26"
  titlebar: "#16171f"
  text: "#a9b1d6"
  text-bright: "#c0caf5"
  text-dim: "#565f89"
  text-muted: "#3b3f5c"
  accent: "#7aa2f7"
  scrollbar: "#2e3154"
  green: "#9ece6a"
  orange: "#ff9e64"
  red: "#f7768e"
  yellow: "#e0af68"
  blue: "#7aa2f7"
  purple: "#bb9af7"
  cyan: "#7dcfff"
  pink: "#ff6ec7"
  tl-red: "#ff5f57"
  tl-yellow: "#febc2e"
  tl-green: "#28c840"

status:
  left: "? for shortcuts · hold Space to speak"
  right: null

icon: "claude"

colors:
  pink: "#ff6ec7"
  yellow: "#e0af68"
  orange: "#ff9e64"
  green: "#9ece6a"
  blue: "#7aa2f7"
  purple: "#bb9af7"
  red: "#f7768e"
  cyan: "#7dcfff"
```

- [ ] **Step 2: Commit**

```bash
git add src/site/tui/shells/claude.yaml
git commit -m "feat(tui): add Claude Code shell config"
```

---

### Task 3: Write demo descriptors

**Files:**
- Create: `src/site/tui/demos/claude/1-briefing.yaml`
- Create: `src/site/tui/demos/claude/2-codex-review.yaml`
- Create: `src/site/tui/demos/claude/3-memory.yaml`

Extract the three existing hardcoded scenes into YAML.

- [ ] **Step 1: Create `1-briefing.yaml`**

```yaml
name: briefing
label: "xgh brief"
label_color: cyan
command: "/xgh-brief"

steps:
  - skill: "xgh:briefing"

  - tool: lcm_search
    args: '"today context, recent work"'
    output: "→ 12 memories matched · last session: 3h ago"
    delay: 700

  - tool: Bash
    args: "git log --oneline -5"
    output:
      - "ba6ccc1 chore: update all public-facing refs to extreme-go-horse org"
      - "c056428 chore: move npm scope to @extreme-go-horse"
      - "9269bcc fix: address Copilot review round-2 comments"
    delay: 500

  - tool: Bash
    args: "gh pr list --limit 5 --json number,title,state"
    output: "#20  feat/agents-md-generator  OPEN"
    delay: 600

  - blank: true

  - response:
      - { bold: "## Session Briefing" }
      - { dim: "─────────────────────────────────────" }
      - { icon: "✓", color: green, bold: "PR #20", dim: "open · awaiting Copilot re-review" }
      - { icon: "✓", color: green, bold: "npm published", dim: "@extreme-go-horse/xgh@2.0.0" }
      - { icon: "→", color: yellow, bold: "5 commits", dim: "since last session" }
      - { dim: "─────────────────────────────────────" }
      - { dim: "Next: merge PR #20 once review is clean" }
```

- [ ] **Step 2: Create `2-codex-review.yaml`**

```yaml
name: codex-review
label: "codex review"
label_color: orange
command: "/xgh-codex review --base main"

steps:
  - skill: "xgh:codex"

  - tool: Bash
    args: "codex --version"
    output: "0.116.0"
    delay: 500

  - response:
      - { dim: "Dispatch type:", blue: " review", dim2: " · target:", yellow: " --base main" }

  - agent: "xgh:codex-driver · dispatching..."
    lines:
      - "sandbox: disk-full-read-access"
      - "dir: /Users/pedro/Developer/xgh"
    delay: 1200

  - tool: Bash
    args: "codex review --base main -c 'sandbox_permissions=[...]'"
    output:
      - "Reviewing 14 changed files vs main..."
      - { green: "✓ No critical issues found" }
      - { yellow: "⚠ 2 suggestions (low priority)" }
    delay: 2200

  - blank: true

  - response:
      - { green: "✓ Codex review complete" }
      - { dim: "0 critical · 2 suggestions · ready to merge" }
```

- [ ] **Step 3: Create `3-memory.yaml`**

```yaml
name: memory
label: "memory"
label_color: purple
input: "how does seed-global-config work?"

steps:
  - tool: lcm_search
    args: '"seed-global-config, marker injection"'
    output:
      - '→ Memory: "uses <!-- xgh:begin --> markers for idempotent injection"'
      - '→ Memory: "arg-count guard added in fix commit 9269bcc"'
    delay: 700

  - tool: Read
    args: "scripts/seed-global-config.sh"
    output: "57 lines · last modified: today"
    delay: 500

  - blank: true

  - response:
      - { bold: "seed-global-config.sh", dim: " — idempotent marker injection" }
      - ""
      - { dim: "Args:", yellow: " <target> <marker-name> <content-file>" }
      - { green: "  1.", dim: " File missing → create with markers" }
      - { green: "  2.", dim: " File exists, no markers → append section" }
      - { green: "  3.", dim: " Markers present → replace only that section" }
      - ""
      - { dim: "Tilde expansion +", yellow: " mkdir -p", dim2: " handle all path cases." }
```

- [ ] **Step 4: Commit**

```bash
git add src/site/tui/demos/
git commit -m "feat(tui): add demo descriptors for 3 scenes"
```

---

### Task 4: Write command descriptors

**Files:**
- Create: `src/site/tui/commands/install.yaml`
- Create: `src/site/tui/commands/about.yaml`
- Create: `src/site/tui/commands/color.yaml`
- Create: `src/site/tui/commands/rename.yaml`
- Create: `src/site/tui/commands/help.yaml`

- [ ] **Step 1: Create `install.yaml`**

```yaml
name: install
command: "/install"
description: "How to install xgh"

response:
  - { bold: "Install xgh" }
  - ""
  - { dim: "1. Install the plugin:" }
  - { blue: "   claude plugin install xgh@extreme-go-horse" }
  - ""
  - { dim: "2. Run first-time setup:" }
  - { blue: "   /xgh-init" }
  - ""
  - { dim: "3. Start your session:" }
  - { blue: "   /xgh-brief" }
  - ""
  - { dim: "Or via npm:", blue: " npm i @extreme-go-horse/xgh" }
```

- [ ] **Step 2: Create `about.yaml`**

```yaml
name: about
command: "/about"
description: "What is xgh"

response:
  - { bold: "xgh — eXtreme Go Horse" }
  - { dim: "Claude on the fastlane. 🐴" }
  - ""
  - { dim: "The developer's cockpit for Claude Code:" }
  - { icon: "✓", color: green, dim: "Persistent memory across sessions (lossless-claude)" }
  - { icon: "✓", color: green, dim: "Context compression — 60–90% token savings" }
  - { icon: "✓", color: green, dim: "9 specialized agents (codex-driver, pr-reviewer…)" }
  - { icon: "✓", color: green, dim: "Automated Slack/Jira/GitHub retrieval" }
  - { icon: "✓", color: green, dim: "Superpowers workflow methodology" }
  - ""
  - { dim: "github.com/extreme-go-horse/xgh" }
```

- [ ] **Step 3: Create `color.yaml`**

```yaml
name: color
command: "/color"
description: "Change prompt accent color for this session"
handler: color
```

- [ ] **Step 4: Create `rename.yaml`**

```yaml
name: rename
command: "/rename"
description: "Set a custom label on the input divider"
handler: rename
```

- [ ] **Step 5: Create `help.yaml`**

```yaml
name: help
command: "/help"
description: "List all commands"
handler: help
```

- [ ] **Step 6: Commit**

```bash
git add src/site/tui/commands/
git commit -m "feat(tui): add command descriptors"
```

---

### Task 5: Build the TUI engine template (`engine.html`)

**Files:**
- Create: `src/site/tui/engine.html`

This is the core — a complete HTML file with CSS (using CSS custom properties for all theme values) and JS (a generic scene player + command runner). It reads `window.__TUI_SHELL`, `window.__TUI_DEMOS`, and `window.__TUI_COMMANDS` injected by the build script.

The JS engine has these responsibilities:
1. **Init** — read shell config, populate header/title/status/model/icon from `__TUI_SHELL`
2. **Scene player** — iterate `steps` array from a demo, render each step type (`skill`, `tool`, `blank`, `response`, `agent`, `input`). Check `demoAbort` after every `await`.
3. **Demo loop** — cycle through `__TUI_DEMOS`, call scene player for each, set divider label/color per scene
4. **Interactive mode** — click-to-focus / type-anywhere entry, autocomplete panel built from `__TUI_COMMANDS`
5. **Command runner** — match input against commands, render `response` lines or invoke built-in handler (`color`, `rename`, `help`)
6. **Built-in handlers** — `color` reads palette from `__TUI_SHELL.colors`, `rename` updates divider label, `help` lists all commands
7. **Icon renderers** — keyed by `__TUI_SHELL.icon` (e.g., `"claude"` draws the pixel-art Claude icon)
8. **Render helpers** — `appendToolBlock`, `resolveToolBlock`, `appendLines`, `appendSkillBadge`, `appendAgentBlock`, `typeInput`, `commitInput`, etc.

The engine template has three placeholder markers where the build script injects data:

```html
<script>
// %%SHELL_DATA%%
// %%DEMOS_DATA%%
// %%COMMANDS_DATA%%
</script>
```

- [ ] **Step 1: Write the CSS section**

All colors reference CSS custom properties (e.g., `var(--bg)`, `var(--text)`, `var(--text-dim)`). The `:root` block has placeholder values that get overwritten by the build script injection. Port all 187 lines of existing CSS, replacing every hardcoded hex with a `var()` reference.

Key mappings from current hex → CSS var:
- `#0d0e17` → `var(--bg)`
- `#1a1b26` → `var(--window)`
- `#16171f` → `var(--titlebar)`
- `#a9b1d6` → `var(--text)`
- `#c0caf5` → `var(--text-bright)`
- `#565f89` → `var(--text-dim)`
- `#3b3f5c` → `var(--text-muted)`
- `#7aa2f7` → `var(--blue)` / `var(--accent)`
- `#9ece6a` → `var(--green)`
- `#ff9e64` → `var(--orange)`
- `#f7768e` → `var(--red)`
- `#e0af68` → `var(--yellow)`
- `#bb9af7` → `var(--purple)`
- `#7dcfff` → `var(--cyan)`
- `#ff6ec7` → `var(--pink)`
- `#2e3154` → `var(--scrollbar)`
- `#4a5080` → `var(--text-muted)` (tool output lines)
- `#7a82b0` → `var(--text-dim)` (title bar bright)
- `#ff5f57` → `var(--tl-red)`
- `#febc2e` → `var(--tl-yellow)`
- `#28c840` → `var(--tl-green)`

- [ ] **Step 2: Write the HTML body**

Same structure as current but with no hardcoded text. All text content (`Claude Code`, `v2.1.81`, `x.com/ipedro`, status bar text) gets populated by JS from `__TUI_SHELL` on init.

```html
<div class="window">
  <div class="title-bar">
    <div class="traffic-lights">
      <div class="tl tl-red"></div>
      <div class="tl tl-yellow"></div>
      <div class="tl tl-green"></div>
    </div>
    <div class="title-text" id="title-text"></div>
  </div>

  <div class="cc-header">
    <canvas class="cc-icon" width="52" height="52" id="cc-icon"></canvas>
    <div class="cc-info">
      <span class="cc-name" id="cc-name"></span>
      <span class="cc-version" id="cc-version"></span>
      <span class="cc-model" id="cc-model"></span>
      <a class="cc-path" id="cc-path"></a>
    </div>
  </div>

  <div class="conversation" id="conv-scroll">
    <div class="conv-inner" id="conv"></div>
  </div>

  <div class="input-divider" id="input-divider">
    <div class="input-label" id="input-label"></div>
  </div>
  <div class="input-row" id="input-row">
    <span class="prompt-chevron" id="prompt-chevron"></span>
    <span class="prompt-input" id="input-text"></span>
    <span class="prompt-cursor" id="cursor"></span>
  </div>
  <div class="autocomplete" id="autocomplete"></div>

  <div class="status-bar">
    <span class="status-left" id="status-left"></span>
    <span class="status-right" id="status-right"></span>
  </div>
</div>
```

- [ ] **Step 3: Write JS — data injection points and init**

```javascript
// ── Data (injected by build.sh) ─────────────────────────────────
// %%SHELL_DATA%%
// %%DEMOS_DATA%%
// %%COMMANDS_DATA%%

// ── Init ────────────────────────────────────────────────────────
const S = window.__TUI_SHELL;
const DEMOS = window.__TUI_DEMOS;
const CMDS = window.__TUI_COMMANDS;

// Populate header from shell config
document.getElementById('cc-name').textContent = S.title;
document.getElementById('cc-version').textContent = S.version;
document.getElementById('cc-model').textContent =
  S.models[Math.floor(Math.random() * S.models.length)];
const pathEl = document.getElementById('cc-path');
pathEl.textContent = S.path.text;
pathEl.href = S.path.url;
pathEl.target = '_blank';
pathEl.rel = 'noopener';
document.getElementById('prompt-chevron').textContent = S.prompt;
document.getElementById('status-left').textContent = S.status.left;
document.getElementById('title-text').innerHTML =
  `<span class="dim">${esc(S.titlebar.text)}</span>` +
  `<span class="dim"> — </span>` +
  `<span class="star">✳</span>` +
  `<span class="bright"> ${esc(S.title)}</span>` +
  `<span class="dim"> ${esc(S.titlebar.detail)}</span>`;
if (S.status.right) {
  document.getElementById('status-right').innerHTML =
    `${esc(S.status.right)}<span class="sep">·</span><span class="status-cmd">/mcp</span>`;
}
```

- [ ] **Step 4: Write JS — render helpers**

Port all existing helpers unchanged: `esc()`, `scrollBottom()`, `sleep()`, `clearConv()`, `typeInput()`, `clearInput()`, `commitInput()`, `assistantTurn()`, `appendToolBlock()`, `resolveToolBlock()`, `appendLines()`, `appendSkillBadge()`, `appendAgentBlock()`, `appendBlank()`. These are already generic — no changes needed, just copy them.

- [ ] **Step 5: Write JS — divider state + interactive mode**

Port: `updateDivider()`, `setDemoContext()`, `applyUserPrefs()`, `enterInteractive()`, `exitInteractive()`, `renderAutocomplete()`, `onKey()`. Change `renderAutocomplete` to read from `CMDS` instead of hardcoded `COMMANDS`:

```javascript
function renderAutocomplete(q) {
  const matches = q.length === 0
    ? CMDS
    : CMDS.filter(c => c.command.includes(q));
  acEl.innerHTML = '';
  matches.forEach((c, i) => {
    const row = document.createElement('div');
    row.className = 'ac-row' + (i === 0 ? ' highlighted' : '');
    row.innerHTML = `<span class="ac-cmd">${esc(c.command)}</span><span class="ac-desc">${esc(c.description)}</span>`;
    row.addEventListener('click', () => submitCommand(c.command));
    acEl.appendChild(row);
  });
}
```

- [ ] **Step 6: Write JS — response line renderer**

A new function that interprets the YAML line format into HTML. This is the key piece that makes response lines data-driven:

```javascript
function renderLine(line) {
  if (typeof line === 'string') return esc(line);
  // Render in fixed precedence: icon, then all styling keys
  let html = '';
  if (line.icon) {
    const color = line.color ? `var(--${line.color})` : 'var(--text)';
    html += `<span style="color:${color}">${esc(line.icon)}</span> `;
  }
  if (line.bold)  html += `<span class="resp-bold">${esc(line.bold)}</span>`;
  if (line.blue)  html += `<span class="resp-blue">${esc(line.blue)}</span>`;
  if (line.green) html += `<span class="resp-green">${esc(line.green)}</span>`;
  if (line.yellow) html += `<span class="resp-yellow">${esc(line.yellow)}</span>`;
  if (line.orange) html += `<span class="resp-orange">${esc(line.orange)}</span>`;
  if (line.red)   html += `<span class="resp-red">${esc(line.red)}</span>`;
  if (line.purple) html += `<span class="resp-accent">${esc(line.purple)}</span>`;
  if (line.cyan)  html += `<span style="color:var(--cyan)">${esc(line.cyan)}</span>`;
  if (line.dim)   html += `<span class="resp-dim">${esc(line.dim)}</span>`;
  if (line.dim2)  html += `<span class="resp-dim">${esc(line.dim2)}</span>`;
  return html;
}
```

- [ ] **Step 7: Write JS — generic scene player**

The core engine: takes a demo object and plays its `steps` array:

```javascript
async function playScene(demo) {
  // Set divider context
  if (demo.label) {
    const color = S.theme[demo.label_color] || S.theme.accent;
    setDemoContext(demo.label, color);
  }

  // Type command or input
  if (demo.command) {
    await typeInput(demo.command);
    if (demoAbort) return;
    await sleep(200);
    commitInput(demo.command);
    cursorEl.classList.add('hidden');
  } else if (demo.input) {
    await typeInput(demo.input);
    if (demoAbort) return;
    await sleep(200);
    commitInput(demo.input);
    cursorEl.classList.add('hidden');
  }

  const at = assistantTurn();

  for (const step of demo.steps) {
    if (demoAbort) return;

    if (step.skill) {
      appendSkillBadge(at, step.skill);
      await sleep(300);

    } else if (step.tool) {
      const tb = appendToolBlock(at, step.tool, step.args);
      const out = Array.isArray(step.output) ? step.output : [step.output];
      const rendered = out.map(o => typeof o === 'string'
        ? `<span class="resp-dim">${esc(o)}</span>`
        : renderLine(o));
      await resolveToolBlock(tb, rendered, step.delay || 600);

    } else if (step.blank) {
      appendBlank(at);

    } else if (step.response) {
      appendLines(at, step.response.map(renderLine));

    } else if (step.agent) {
      const lines = (step.lines || []).map(l =>
        `<span class="resp-dim">${typeof l === 'string' ? esc(l) : renderLine(l)}</span>`);
      appendAgentBlock(at, step.agent, lines);
      if (step.delay) await sleep(step.delay);

    } else if (step.input) {
      await sleep(800);
      await typeInput(step.input);
      if (demoAbort) return;
      await sleep(200);
      commitInput(step.input);
      cursorEl.classList.add('hidden');
    }
  }

  await sleep(1000);
  cursorEl.classList.remove('hidden');
}
```

- [ ] **Step 8: Write JS — command runner**

```javascript
async function submitCommand(cmd) {
  if (!cmd) return;
  acEl.classList.remove('visible');
  commitInput(cmd);

  const at = assistantTurn();

  // Check built-in handlers first
  const baseCmd = cmd.split(/\s+/)[0];
  const cmdDef = CMDS.find(c => c.command === baseCmd);

  if (cmdDef && cmdDef.handler) {
    await runHandler(cmdDef.handler, at, cmd);
  } else if (cmdDef && cmdDef.response) {
    await sleep(200);
    appendLines(at, cmdDef.response.map(renderLine));
  } else {
    // Check if it matches a demo command (e.g., /xgh-brief)
    const demo = DEMOS.find(d => d.command === cmd);
    if (demo) {
      await playScene(demo);
    } else {
      appendLines(at, [
        `<span class="resp-dim">Unknown command: <span class="resp-red">${esc(cmd)}</span></span>`,
        `<span class="resp-dim">Type <span class="resp-blue">/help</span> to see available commands.</span>`,
      ]);
    }
  }

  await sleep(400);
  typedValue = '';
  inputEl.textContent = '';
  acEl.classList.add('visible');
  renderAutocomplete('');
}
```

- [ ] **Step 9: Write JS — built-in handlers (color, rename, help)**

```javascript
async function runHandler(handler, at, cmd) {
  if (handler === 'color') {
    const name = cmd.split(/\s+/)[1];
    if (!name) {
      appendLines(at, [
        `<span class="resp-bold">Available colors:</span>`,
        ...Object.keys(S.colors).map(c =>
          `  <span style="color:${S.colors[c]}">■</span> <span class="resp-dim">${esc(c)}</span>`
        ),
        ``, `<span class="resp-dim">Usage: <span class="resp-blue">/color &lt;name&gt;</span></span>`,
      ]);
    } else if (S.colors[name]) {
      userPrefs.color = S.colors[name];
      applyUserPrefs();
      appendLines(at, [
        `<span style="color:${S.colors[name]}">■</span> Prompt color set to <span style="color:${S.colors[name]};font-weight:600">${esc(name)}</span>`,
      ]);
    } else {
      appendLines(at, [`<span class="resp-red">Unknown color: ${esc(name)}</span>`]);
    }

  } else if (handler === 'rename') {
    const name = cmd.replace(/^\/rename\s*/, '').trim();
    if (!name) {
      userPrefs.label = null;
      applyUserPrefs();
      appendLines(at, [`<span class="resp-dim">Label cleared.</span>`]);
    } else {
      userPrefs.label = name;
      applyUserPrefs();
      appendLines(at, [
        `<span class="resp-dim">Label set to </span><span class="resp-bold">${esc(name)}</span>`,
      ]);
    }

  } else if (handler === 'help') {
    await sleep(200);
    appendLines(at, [`<span class="resp-bold">Available commands:</span>`, ``]);
    CMDS.forEach(c => {
      const d = document.createElement('div');
      d.className = 'resp-text';
      d.innerHTML = `  <span class="resp-blue">${esc(c.command)}</span>  <span class="resp-dim">${esc(c.description)}</span>`;
      at.appendChild(d);
    });
    appendLines(at, [``, `<span class="resp-dim">Press <span class="resp-yellow">Esc</span> to return to demo mode.</span>`]);
  }
}
```

- [ ] **Step 10: Write JS — demo loop + icon renderer**

```javascript
// Demo loop
async function runDemo() {
  demoAbort = false;
  demoRunning = true;
  clearConv();

  while (!demoAbort) {
    for (const demo of DEMOS) {
      if (demoAbort) break;
      await playScene(demo);
      if (demoAbort) break;
      await sleep(1500);
      if (demoAbort) break;
      clearConv();
    }
  }
  demoRunning = false;
}

// Icon renderers (keyed by shell.icon)
const ICONS = {
  claude(canvas) {
    const ctx = canvas.getContext('2d');
    const Sc = 3.25;
    const O = '#C87941', D = S.theme.window, B = '#A8622F';
    const px = [
      [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
      [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
      [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
      [0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0],
      [0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0],
      [0,0,0,1,1,2,2,1,1,2,2,1,1,0,0,0],
      [0,0,0,1,1,2,2,1,1,2,2,1,1,0,0,0],
      [0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0],
      [0,0,0,1,1,2,2,2,2,2,2,1,1,0,0,0],
      [0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0],
      [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
      [0,0,0,3,3,1,1,3,3,1,1,3,3,0,0,0],
      [0,0,0,3,3,1,1,3,3,1,1,3,3,0,0,0],
      [0,0,0,3,3,3,3,3,3,3,3,3,3,0,0,0],
      [0,0,0,3,3,3,3,3,3,3,3,3,3,0,0,0],
      [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
    ];
    for (let r = 0; r < 16; r++)
      for (let c = 0; c < 16; c++) {
        const v = px[r][c];
        if (!v) continue;
        ctx.fillStyle = v === 1 ? O : v === 2 ? D : B;
        ctx.fillRect(c * Sc, r * Sc, Sc, Sc);
      }
  },
};

// Draw icon on init
if (ICONS[S.icon]) ICONS[S.icon](document.getElementById('cc-icon'));

// Start
runDemo();
```

- [ ] **Step 11: Verify engine.html renders correctly in isolation**

Open the file in browser with temporary hardcoded data to confirm CSS variables, scene player, and interactive mode work.

```bash
open src/site/tui/engine.html
```

Expected: renders the TUI with all three demo scenes cycling, interactive mode working on click/type, `/color`, `/rename`, `/help` commands functional.

- [ ] **Step 12: Commit**

```bash
git add src/site/tui/engine.html
git commit -m "feat(tui): data-driven engine template"
```

---

### Task 6: Build script (`build.sh`)

**Files:**
- Create: `src/site/tui/build.sh`

- [ ] **Step 1: Write the build script**

```bash
#!/usr/bin/env bash
set -euo pipefail

SHELL_NAME="${1:?Usage: build.sh <shell-name>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check PyYAML
if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "ERROR: PyYAML required. Install with: pip3 install pyyaml" >&2
  exit 1
fi

# Paths
SHELL_FILE="$SCRIPT_DIR/shells/${SHELL_NAME}.yaml"
DEMOS_DIR="$SCRIPT_DIR/demos/${SHELL_NAME}"
CMDS_DIR="$SCRIPT_DIR/commands"
ENGINE="$SCRIPT_DIR/engine.html"
OUT_DIR="$SCRIPT_DIR/out"
OUT_FILE="$OUT_DIR/${SHELL_NAME}-tui.html"

# Validate inputs exist
[ -f "$SHELL_FILE" ] || { echo "ERROR: Shell config not found: $SHELL_FILE" >&2; exit 1; }
[ -d "$DEMOS_DIR" ]  || { echo "ERROR: Demos dir not found: $DEMOS_DIR" >&2; exit 1; }
[ -f "$ENGINE" ]     || { echo "ERROR: Engine template not found: $ENGINE" >&2; exit 1; }

mkdir -p "$OUT_DIR"

# Convert YAML → JSON
yaml2json() { python3 -c "import yaml,json,sys; print(json.dumps(yaml.safe_load(sys.stdin),indent=2))"; }
yaml2json_array() {
  python3 -c "
import yaml, json, sys, os, glob
files = sorted(glob.glob(sys.argv[1]))
result = [yaml.safe_load(open(f)) for f in files]
print(json.dumps(result, indent=2))
" "$1"
}

SHELL_JSON=$(yaml2json < "$SHELL_FILE")
DEMOS_JSON=$(yaml2json_array "$DEMOS_DIR/*.yaml")
CMDS_JSON=$(yaml2json_array "$CMDS_DIR/*.yaml")

# Generate CSS custom properties from shell theme
CSS_VARS=$(python3 -c "
import yaml, sys
shell = yaml.safe_load(open('$SHELL_FILE'))
theme = shell.get('theme', {})
lines = []
for k, v in theme.items():
    lines.append(f'--{k}: {v};')
print(' '.join(lines))
")

# Inject into engine template
python3 -c "
import sys
engine = open('$ENGINE').read()

# Inject CSS vars into :root
engine = engine.replace('/* %%CSS_VARS%% */', '''$CSS_VARS''')

# Inject data
engine = engine.replace('// %%SHELL_DATA%%', 'window.__TUI_SHELL = $SHELL_JSON;')
engine = engine.replace('// %%DEMOS_DATA%%', 'window.__TUI_DEMOS = $DEMOS_JSON;')
engine = engine.replace('// %%COMMANDS_DATA%%', 'window.__TUI_COMMANDS = $CMDS_JSON;')

with open('$OUT_FILE', 'w') as f:
    f.write(engine)
"

echo "Built: $OUT_FILE"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x src/site/tui/build.sh
```

- [ ] **Step 3: Run the build and verify output**

```bash
bash src/site/tui/build.sh claude
open src/site/tui/out/claude-tui.html
```

Expected: the generated file renders identically to the current `claude-tui.html` — same demo scenes, same interactive mode, same commands.

- [ ] **Step 4: Commit**

```bash
git add src/site/tui/build.sh src/site/tui/out/claude-tui.html
git commit -m "feat(tui): build script + first generated output"
```

---

### Task 7: Verification and cleanup

**Files:**
- Modify: `src/site/index.html` (update TUI embed path if needed)

- [ ] **Step 1: Visual comparison**

Open both the old and new TUI side-by-side:

```bash
open /Users/pedro/Developer/extreme-go-horse.com/claude-tui.html
open src/site/tui/out/claude-tui.html
```

Verify:
- Demo scenes play identically (same tool calls, same output text, same timing)
- Interactive mode: click focuses, type anywhere activates, autocomplete panel shows
- `/color pink` changes accent, `/rename test` sets label, `/help` lists commands
- Divider shows scene label during demo, resets to user prefs in interactive
- Random model on each reload
- `x.com/ipedro` is a clickable link

- [ ] **Step 2: Commit final state**

```bash
git add -A src/site/
git commit -m "feat(tui): modular TUI engine complete — YAML-driven demos + commands"
```

---

### Summary

| Task | What it produces | Files |
|------|-----------------|-------|
| 1 | Site migration | `src/site/index.html` |
| 2 | Shell config | `shells/claude.yaml` |
| 3 | Demo descriptors | `demos/claude/*.yaml` (3 files) |
| 4 | Command descriptors | `commands/*.yaml` (5 files) |
| 5 | Engine template | `engine.html` (~600 lines) |
| 6 | Build pipeline | `build.sh` + generated `out/claude-tui.html` |
| 7 | Verification | Visual comparison, final commit |
