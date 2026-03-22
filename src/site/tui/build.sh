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

# Convert to JSON strings
shell_json = json.dumps(shell_data, indent=2)
demos_json = json.dumps(demos_data, indent=2)
cmds_json = json.dumps(cmds_data, indent=2)

# Read engine template
with open(engine_file) as f:
    engine = f.read()

# Inject data
engine = engine.replace('/* %%CSS_VARS%% */', css_vars)
engine = engine.replace('// %%SHELL_DATA%%', f'window.__TUI_SHELL = {shell_json};')
engine = engine.replace('// %%DEMOS_DATA%%', f'window.__TUI_DEMOS = {demos_json};')
engine = engine.replace('// %%COMMANDS_DATA%%', f'window.__TUI_COMMANDS = {cmds_json};')

# Write output
os.makedirs(os.path.dirname(out_file), exist_ok=True)
with open(out_file, 'w') as f:
    f.write(engine)

print(f'Built: {out_file}')
PYEOF
