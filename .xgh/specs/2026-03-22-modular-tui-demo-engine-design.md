# Modular TUI Demo Engine — Design Spec

> **Goal:** Replace the monolithic `claude-tui.html` with a data-driven TUI engine that reads YAML descriptors to render animated demo scenes and interactive commands. Move the website into the xgh repo at `src/site/`. Enable future shells (Codex, Gemini) using the same engine.

## Architecture

Three layers:

1. **TUI engine** — a generic HTML template that plays scenes and runs commands from injected JSON data
2. **Declarative descriptors** — YAML files that script demo choreography and command responses
3. **Build pipeline** — a shell script that reads shell config + demos + commands → produces a single HTML file

The website moves from the separate `extreme-go-horse.com` repo into `src/site/` in the xgh repo. The npm `package.json` `files` field already limits publishing to `.claude-plugin/`, so the site won't ship to npm.

## File Structure

```
src/site/
  index.html                        # landing page (moved from extreme-go-horse.com)
  tui/
    engine.html                     # generic TUI renderer (CSS + scene player + command runner)
    build.sh                        # YAML → JSON → inject into engine → output HTML
    shells/
      claude.yaml                   # Claude Code visual identity
      codex.yaml                    # (future) Codex CLI visual identity
      gemini.yaml                   # (future) Gemini CLI visual identity
    demos/
      claude/
        briefing.yaml               # scene: /xgh-brief
        codex-review.yaml           # scene: /xgh-codex review --base main
        memory.yaml                 # scene: how does seed-global-config work?
      codex/                        # (future)
      gemini/                       # (future)
    commands/
      install.yaml                  # interactive: /install
      about.yaml                    # interactive: /about
      help.yaml                     # auto-generated at build time from all commands
      color.yaml                    # built-in handler: /color <name>
      rename.yaml                   # built-in handler: /rename <name>
    out/
      claude-tui.html               # generated output
```

## Shell Config Format

`shells/claude.yaml` defines the visual identity for one TUI shell:

```yaml
name: claude
title: "Claude Code"
version: "v2.1.81"
path:
  text: "x.com/ipedro"
  url: "https://x.com/ipedro"
prompt: "›"
models:
  - "Sonnet 4.6 with medium effort · Claude Max"
  - "Sonnet 4.6 with high effort · Claude Max"
  - "Opus 4.6 with medium effort · Claude Max"
  - "Opus 4.6 · Claude Max"
  - "Haiku 4.5 · Claude Max"
  - "Sonnet 4.6 · Claude Pro"
theme:
  bg: "#1a1b26"
  titlebar: "#16171f"
  text: "#a9b1d6"
  text-bright: "#c0caf5"
  text-dim: "#565f89"
  text-muted: "#3b3f5c"
  accent: "#7aa2f7"
  green: "#9ece6a"
  orange: "#ff9e64"
  red: "#f7768e"
  yellow: "#e0af68"
  blue: "#7aa2f7"
  purple: "#bb9af7"
  cyan: "#7dcfff"
  pink: "#ff6ec7"
status:
  left: "? for shortcuts · hold Space to speak"
  right: null
icon: "claude"
```

All CSS values (colors, backgrounds, borders) are derived from the theme at build time. No hardcoded colors in the engine template.

## Demo Descriptor Format

Each YAML file in `demos/<shell>/` defines one animated scene:

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

### Step types

| Type | Purpose | Fields |
|------|---------|--------|
| `skill` | Renders a skill badge | `skill: "name"` |
| `tool` | Tool call with spinner → resolved output | `tool`, `args`, `output` (string or list), `delay` (ms) |
| `blank` | Vertical spacer | `blank: true` |
| `response` | Styled text lines | List of line objects with `bold`, `dim`, `color`, `icon`, `blue`, etc. |
| `agent` | Agent dispatch block (green border) | `agent: "label"`, `lines: [...]` |
| `input` | Typed-out user prompt (non-command) | `input: "how does X work?"` |

### Response line format

Each line in a `response` block is an object with styling keys:

- `bold: "text"` — bright, bold
- `dim: "text"` — muted
- `blue: "text"` — blue colored
- `color: <name>` — theme color for the icon/prefix
- `icon: "✓"` — prefix character (colored by `color`)
- Plain string `""` — empty line

Multiple keys on one line are concatenated in order.

## Command Descriptor Format

Each YAML file in `commands/` defines one interactive command:

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
  - { dim: "Or via npm:", blue: "npm i @extreme-go-horse/xgh" }
```

Commands with special behavior use a `handler` field instead of `response`:

```yaml
name: color
command: "/color"
description: "Change prompt accent color for this session"
handler: color
```

```yaml
name: help
command: "/help"
description: "List all commands"
handler: help
```

Built-in handlers: `color`, `rename`, `help`. The `help` handler is auto-generated from all commands at build time.

## Build Pipeline

`build.sh <shell-name>` (e.g., `build.sh claude`):

1. Parse `shells/<shell-name>.yaml` → JSON
2. Parse all `demos/<shell-name>/*.yaml` → JSON array (sorted by filename)
3. Parse all `commands/*.yaml` → JSON array
4. Read `engine.html` template
5. Inject three JSON blobs:
   - `window.__TUI_SHELL = { ... }`
   - `window.__TUI_DEMOS = [ ... ]`
   - `window.__TUI_COMMANDS = [ ... ]`
6. Write `out/<shell-name>-tui.html`

<<<<<<< HEAD
Dependencies: `bash`, Python 3 with PyYAML (`pip3 install pyyaml`). The build script checks for PyYAML at startup and prints install instructions if missing. No npm, no bundler.
=======
Dependencies: `bash`, Python 3 (for YAML→JSON via `python3 -c 'import yaml, json, sys; ...'`). No npm, no bundler.
>>>>>>> origin/develop

## TUI Engine (`engine.html`)

The engine template contains:

- **CSS** — all styles use CSS custom properties derived from the shell theme (injected as `:root { --bg: ...; --text: ...; }`)
- **HTML** — window chrome, header, conversation area, input area, autocomplete panel, status bar. All text content comes from shell config.
- **Scene player** — generic function that iterates a demo's `steps` array and renders each step type. Handles `demoAbort` interruption at every async point.
- **Command runner** — matches typed input against `__TUI_COMMANDS`, renders `response` lines or invokes built-in `handler`.
- **Interactive mode** — same click-to-focus / type-anywhere behavior. Reads commands from `__TUI_COMMANDS` for autocomplete.
- **Demo loop** — cycles through `__TUI_DEMOS`, calling the scene player for each. Sets `label` + `label_color` on the divider per scene.
- **Built-in handlers** — `color` (reads palette from shell theme), `rename` (sets divider label), `help` (lists commands from `__TUI_COMMANDS`).
- **Icon renderers** — pixel-art functions keyed by `icon` field in shell config (e.g., `"claude"` renders the orange Claude icon).

## Generation Trigger

An xgh trigger to auto-rebuild when skill files change:

```yaml
schema_version: 1
name: site-demo-sync
<<<<<<< HEAD
description: "Rebuild TUI demos when a skill file is written or edited"
=======
description: "Rebuild TUI demos when skill files change"
>>>>>>> origin/develop
enabled: true

when:
  source: local
<<<<<<< HEAD
  command: ".*skills/.*"    # regex matched against Write/Edit tool paths
=======
  command: "*skills/*"
>>>>>>> origin/develop

path: fast

cooldown: 30s
backoff: none

<<<<<<< HEAD
action_level: create

then:
  - name: Rebuild TUI
    shell: bash
    run: |
      cd "$(git rev-parse --show-toplevel)"
      bash src/site/tui/build.sh claude
    on_error: continue
=======
then:
  - name: Rebuild TUI
    action_type: shell
    run: "bash src/site/tui/build.sh claude"
>>>>>>> origin/develop
```

This is the automation layer. The initial implementation works without it — write YAMLs by hand, run `build.sh` manually. The trigger is added once the pipeline is stable.

## Migration

Move content from `extreme-go-horse.com` repo:

1. Copy `index.html` → `src/site/index.html`
2. The current `claude-tui.html` is replaced by the generated `out/claude-tui.html`
3. Update any deploy config to point at `src/site/`
4. Archive or deprecate the `extreme-go-horse.com` repo

## Future Extensions

- **Codex/Gemini shells** — add `shells/codex.yaml` + `demos/codex/*.yaml`, run `build.sh codex`
- **Mirror xgh command list** — a generation step reads `skills/*/` frontmatter and produces `commands/*.yaml` entries, keeping the interactive menu in sync with the actual plugin
- **Landing page generation** — extend `build.sh` to also update `index.html` feature cards from the same demo descriptors
