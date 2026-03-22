# Single-Scroll Landing Page — Design Spec

> **Goal:** Build a YAML-driven single-scroll landing page with the TUI demo as hero, feature cards below, install instructions, and a minimal footer. Marketing tone — punchy copy, not docs. The README handles technical depth.

## Architecture

Extends the existing TUI build pipeline. `build.sh` gains a second output: `out/index.html` produced from `src/site/template.html` + feature YAMLs + existing TUI/command data. One self-contained HTML file with the TUI embedded inline (not iframe).

## Page Sections

### 1. Hero

- Tagline: "Your AI rides faster." (or similar — set in shell config)
- The TUI window, embedded inline, autoplay demos running
- Install command in TUI header styled as a clickable badge — click copies `claude plugin install xgh@extreme-go-horse` to clipboard with a "Copied!" flash
- Subtle scroll indicator below the TUI

No subtitle, no logos, no social proof. Just the TUI selling itself.

### 2. Feature Cards

A responsive grid (2-3 columns desktop, 1 column mobile) of cards driven by `src/site/features/*.yaml`.

Each card: icon, headline, one-liner description. No bullet points, no code.

### 3. Install

Anchored at `#install`. Three styled steps reusing data from `commands/install.yaml`:

1. Install the plugin: `claude plugin install xgh@extreme-go-horse`
2. Run first-time setup: `/xgh-init`
3. Start your session: `/xgh-brief`

Plus the npm alternative: `npm i @extreme-go-horse/xgh`

### 4. Footer

Minimal — GitHub link, npm link, author. Tagline: "xgh: Claude on the fastlane."

## File Structure

```
src/site/
  template.html                # landing page template with markers
  features/
    memory.yaml
    briefing.yaml
    dispatch.yaml
    compression.yaml
    methodology.yaml
    debugging.yaml
  tui/                         # existing (unchanged)
    engine.html
    build.sh                   # extended to also produce landing page
    shells/claude.yaml
    demos/claude/*.yaml
    commands/*.yaml
    out/
      claude-tui.html          # existing TUI output
      index.html               # NEW: generated landing page
```

## Feature YAML Format

Each file in `src/site/features/`:

```yaml
name: memory
headline: "Memory that persists"
description: "Your agent remembers decisions, patterns, and context across sessions. No more re-explaining."
icon: "🧠"
order: 1
```

Fields:
- `name` — identifier
- `headline` — short, punchy (3-5 words)
- `description` — one sentence, marketing tone
- `icon` — emoji
- `order` — sort position in the grid

## TUI Install Badge

The TUI path element (`cc-path`) becomes a clickable copy-to-clipboard button:

- Default state: shows `claude plugin install xgh@extreme-go-horse` styled as a subtle badge
- On click: copies install command to clipboard, flashes "Copied!" for 1.5s, then reverts
- Keeps the `#install` href as fallback for right-click → open in new tab

Implementation: add a `click` handler in `engine.html` that calls `navigator.clipboard.writeText()`, swaps text content, then restores after timeout.

## Build Pipeline Extension

`build.sh claude` currently produces `out/claude-tui.html`. Extended behavior:

1. Parse `shells/claude.yaml` → JSON (existing)
2. Parse `demos/claude/*.yaml` → JSON (existing)
3. Parse `commands/*.yaml` → JSON (existing)
4. **NEW:** Parse `../features/*.yaml` → JSON array (sorted by `order`)
5. Produce `out/claude-tui.html` from `engine.html` (existing)
6. **NEW:** Read `../template.html`
7. **NEW:** Inline the generated TUI HTML into the template (embed, not iframe)
8. **NEW:** Inject features JSON → render feature cards
9. **NEW:** Inject install data from commands → render install section
10. **NEW:** Write `out/index.html`

The template uses the same marker convention: `<!-- %%TUI_EMBED%% -->`, `<!-- %%FEATURES%% -->`, `<!-- %%INSTALL%% -->`.

Since the landing page needs rendered HTML (not JSON blobs), the Python build step renders the feature cards and install section as HTML strings before injection. The template contains the CSS and structural HTML; the build injects populated content sections.

## Template Design

The `template.html` contains:

- **CSS** — uses the same CSS custom properties from the TUI shell theme for visual consistency. Dark mode, JetBrains Mono, same color palette.
- **Hero section** — tagline text (from shell config), `<!-- %%TUI_EMBED%% -->` marker, scroll indicator
- **Features section** — `<!-- %%FEATURES%% -->` marker where rendered card HTML is injected
- **Install section** — `<!-- %%INSTALL%% -->` marker where rendered install HTML is injected
- **Footer** — static content with repo/npm links

## Styling Approach

- Same dark theme as the TUI — no visual jarring between hero and page
- CSS custom properties from `shells/claude.yaml` theme applied to the whole page
- Feature cards: subtle border, icon left-aligned, headline bold, description dim
- Responsive: cards go from 3-col → 2-col → 1-col
- Smooth scroll between sections
- Scroll-triggered fade-in for feature cards (CSS `animation` with `IntersectionObserver`)

## Scope Exclusions

- No JavaScript framework — vanilla HTML/CSS/JS like the TUI
- No separate CSS file — everything inline for single-file deployment
- No analytics, tracking, or third-party scripts
- No dark/light mode toggle — dark only
- The trigger for auto-rebuilding when skill files change is deferred (same as TUI spec)
