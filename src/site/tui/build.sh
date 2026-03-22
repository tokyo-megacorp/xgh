#!/usr/bin/env bash
set -euo pipefail

export SHELL_NAME="${1:?Usage: build.sh <shell-name>}"
export SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

# Build using Python for reliable YAML→JSON + template injection
python3 << 'PYEOF'
import yaml, json, sys, os, glob

script_dir = os.environ.get('SCRIPT_DIR')
shell_name = os.environ['SHELL_NAME']

shell_file = os.path.join(script_dir, 'shells', f'{shell_name}.yaml')
demos_dir = os.path.join(script_dir, 'demos', shell_name)
cmds_dir = os.path.join(script_dir, 'commands')
engine_file = os.path.join(script_dir, 'engine.html')
out_file = os.path.join(script_dir, 'out', f'{shell_name}-tui.html')

# Parse YAML files
with open(shell_file) as f:
    shell_data = yaml.safe_load(f)

demo_files = sorted(glob.glob(os.path.join(demos_dir, '*.yaml')))
demos_data = []
for df in demo_files:
    with open(df) as f:
        demos_data.append(yaml.safe_load(f))

cmd_files = sorted(glob.glob(os.path.join(cmds_dir, '*.yaml')))
cmds_data = []
for cf in cmd_files:
    with open(cf) as f:
        cmds_data.append(yaml.safe_load(f))

# Generate CSS custom properties from theme
theme = shell_data.get('theme', {})
css_vars = ' '.join(f'--{k}: {v};' for k, v in theme.items())

# Add demo-derived commands to cmds so they appear in /help and autocomplete
existing_cmds = {c.get('command') for c in cmds_data}
for demo in demos_data:
    cmd = demo.get('command')
    if cmd and cmd not in existing_cmds:
        cmds_data.append({
            'name': demo.get('name', cmd),
            'command': cmd,
            'description': 'Demo: ' + demo.get('label', demo.get('name', cmd))
        })

# Convert to JSON strings
shell_json = json.dumps(shell_data, indent=2)
demos_json = json.dumps(demos_data, indent=2)
cmds_json = json.dumps(cmds_data, indent=2)

# Read engine template
with open(engine_file) as f:
    engine = f.read()

# Inject data
page_title = f'{shell_data.get("title", shell_name)} — TUI Demo'
engine = engine.replace('/* %%PAGE_TITLE%% */', page_title)
engine = engine.replace('/* %%CSS_VARS%% */', css_vars)
engine = engine.replace('// %%SHELL_DATA%%', f'window.__TUI_SHELL = {shell_json};')
engine = engine.replace('// %%DEMOS_DATA%%', f'window.__TUI_DEMOS = {demos_json};')
engine = engine.replace('// %%COMMANDS_DATA%%', f'window.__TUI_COMMANDS = {cmds_json};')

# Write output
os.makedirs(os.path.dirname(out_file), exist_ok=True)
with open(out_file, 'w') as f:
    f.write(engine)

print(f'Built: {out_file}')

# ── Landing page generation ───────────────────────────────────────────────────
import re

# Parse feature YAML files
features_dir = os.path.join(script_dir, '..', 'features')
feature_files = sorted(glob.glob(os.path.join(features_dir, '*.yaml')))
features_data = []
for ff in feature_files:
    with open(ff) as f:
        features_data.append(yaml.safe_load(f))
features_data.sort(key=lambda x: x.get('order', 99))

# Read landing page template
template_file = os.path.join(script_dir, '..', 'template.html')
if not os.path.exists(template_file):
    print('Skipping landing page (no template.html)')
    sys.exit(0)

with open(template_file) as f:
    page = f.read()

# Inject per-feature content into named markers
for feat in features_data:
    name = feat.get('name', '').upper()
    if not name:
        continue
    page = page.replace(f'<!-- %%FEAT_{name}_ICON%% -->', feat.get('icon', ''))
    page = page.replace(f'<!-- %%FEAT_{name}_HEADLINE%% -->', feat.get('headline', ''))
    page = page.replace(f'<!-- %%FEAT_{name}_DESC%% -->', feat.get('description', ''))
    page = page.replace(f'<!-- %%FEAT_{name}_DETAIL%% -->', feat.get('detail', ''))

# Render install section HTML from commands/install.yaml
install_cmd = next((c for c in cmds_data if c.get('name') == 'install'), None)
install_html = '<ol class="install-steps">\n'
ol_open = True
if install_cmd and install_cmd.get('response'):
    for line in install_cmd['response']:
        if not isinstance(line, dict):
            continue
        if 'dim' in line and 'blue' in line:
            # Combined line: "Or via npm: npm i ..."
            if ol_open:
                install_html += '</ol>\n'
                ol_open = False
            install_html += f'<p class="install-alt">{line["dim"]} <code>{line["blue"].strip()}</code></p>\n'
        elif 'dim' in line and line['dim'][0:1].isdigit():
            # Step label: "1. Install the plugin:"
            label = line['dim'].split('.', 1)[1].strip().rstrip(':')
            install_html += f'<li class="install-step"><span class="install-label">{label}</span>\n'
        elif 'blue' in line and line['blue'].strip():
            # Step command
            install_html += f'  <code class="install-cmd">{line["blue"].strip()}</code></li>\n'
if ol_open:
    install_html += '</ol>\n'

# Read generated TUI HTML for inline embedding
with open(out_file) as f:
    tui_html = f.read()

# Extract <body> content and <style> from TUI
style_match = re.search(r'<style>(.*?)</style>', tui_html, re.DOTALL)
tui_style = style_match.group(1) if style_match else ''

body_match = re.search(r'<body>(.*)</body>', tui_html, re.DOTALL)
tui_body = body_match.group(1).strip() if body_match else ''

# Scope TUI CSS so it doesn't leak into the landing page
# Strip html/:root rules entirely
tui_style = re.sub(r'\bhtml\s*\{[^}]*\}', '', tui_style)
tui_style = re.sub(r':root\s*\{[^}]*\}', '', tui_style)
# Replace body selector with .tui-embed
tui_style = re.sub(r'\bbody\s*\{', '.tui-embed {', tui_style)
# Scope universal selector: *, *::before, *::after → .tui-embed *, ...
# Lookbehind/lookahead exclude * inside CSS comments (/* ... */)
tui_style = re.sub(r'(?<![.\w/=-])\*(?!/)', '.tui-embed *', tui_style)

# Split body into HTML structure and scripts
parts = re.split(r'(<script>)', tui_body, maxsplit=1)
tui_structure = parts[0].strip()
tui_scripts = '<script>' + parts[2] if len(parts) > 2 else ''

# Wrap structure in scoping div
tui_embed = f'<style>\n{tui_style}\n</style>\n<div class="tui-embed">\n{tui_structure}\n</div>\n{tui_scripts}'

# Inject into page template
page = page.replace('/* %%CSS_VARS%% */', css_vars)
page = page.replace('<!-- %%TUI_EMBED%% -->', tui_embed)
page = page.replace('<!-- %%INSTALL%% -->', install_html)

page_out = os.path.join(script_dir, 'out', 'index.html')
with open(page_out, 'w') as f:
    f.write(page)

print(f'Built: {page_out}')
PYEOF
