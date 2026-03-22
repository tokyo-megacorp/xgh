---
name: xgh:config
description: >
  Structured YAML editor for ~/.xgh/ingest.yaml. Supports showing sections (dot-path),
  setting values with type validation, adding/removing projects interactively,
  and validating all projects for required fields (stack, surfaces, github) and type correctness.
type: flexible
triggers:
  - when the user runs /xgh-config
  - when the user says "edit config", "configure project", "add project to xgh"
---

# xgh:config — Manifest Editor

Parse `$ARGUMENTS` to determine subcommand and route accordingly.

## Subcommand: show [section]

Read `~/.xgh/ingest.yaml` using Python 3 + PyYAML:

```python
import yaml
from pathlib import Path

yaml_path = Path.home() / '.xgh' / 'ingest.yaml'
if not yaml_path.exists():
    print("ERROR: ~/.xgh/ingest.yaml not found. Run /xgh-init first.")
    exit(1)

manifest = yaml.safe_load(yaml_path.read_text())
```

If no section specified: pretty-print the full manifest using `yaml.dump(manifest, default_flow_style=False, sort_keys=False)`.

If section specified (e.g., `projects.xgh.stack`): navigate the dot-path and pretty-print the target value.
- `projects` → print manifest["projects"] (all projects)
- `projects.xgh` → print manifest["projects"]["xgh"]
- `projects.xgh.stack` → print manifest["projects"]["xgh"]["stack"]

If path not found: report "ERROR: path not found in manifest".

## Subcommand: set <path> <value>

Parse dot-path and value, then update `~/.xgh/ingest.yaml` with type validation:

1. **Load manifest** via PyYAML
2. **Navigate path** and split into parent + key (e.g., `projects.xgh.stack` → parent=`projects.xgh`, key=`stack`)
3. **Validate type**:
   - If `projects.<name>.stack`: value must be a string. Allowed: `shell`, `typescript`, `swift`, `kotlin`, `go`, `rust`, `python`, `generic`.
   - If `projects.<name>.surfaces`: value must be a JSON array of objects with `type` key. Parse the value as JSON and validate.
   - If other: accept value as-is (string, number, boolean, list, dict depending on context)
4. **Set value** in manifest (create intermediate dicts if needed)
5. **Write back** to `~/.xgh/ingest.yaml` using `yaml.safe_dump(manifest, default_flow_style=False, sort_keys=False)`
6. **Report success**: "Updated projects.xgh.stack = shell"

If validation fails: report specific error (e.g., "ERROR: stack must be one of: shell, typescript, ...").

## Subcommand: add-project <name>

Interactive flow using AskUserQuestion tool:

1. **Validate project name** (not already in manifest)
2. **Ask GitHub repo**: "Enter GitHub repository (org/repo format)"
   - Validate format with regex `^[a-z0-9-]+/[a-z0-9-_.]+$`
3. **Ask Stack**: "Choose stack type" (shell, typescript, swift, kotlin, go, rust, python, generic)
   - Show as numbered list for user to select
4. **Ask Surfaces**: "Select exposed surfaces (comma-separated from: cli, api, web, mobile, library, plugin, sdk)"
   - Parse as comma-separated list
   - Validate each entry is in allowed set
   - Convert to YAML list of objects: `[{type: cli}, {type: plugin}]`
5. **Create project block**:
   ```yaml
   <name>:
     status: active
     github: [org/repo]
     stack: <selected>
     surfaces:
       - type: cli
       - type: plugin
   ```
6. **Add to manifest["projects"]**
7. **Write back to file**
8. **Report**: "Added project <name> (stack: shell, surfaces: cli, plugin)"

## Subcommand: remove-project <name>

1. **Check project exists** in manifest
2. **Ask user to confirm**: "Remove project '<name>'? (yes/no)"
3. If confirmed: delete from `manifest["projects"]`
4. **Write back to file**
5. **Report**: "Removed project <name>"

## Subcommand: validate

Check all projects under `manifest["projects"]`:

For each project:
1. **Check required fields**: `stack`, `surfaces`, `github`
   - Report missing: "❌ <project>: missing 'stack'"
2. **Check types**:
   - `stack` must be a string. Report: "❌ <project>: stack must be string, got {type}"
   - `surfaces` must be a list. Report: "❌ <project>: surfaces must be list, got {type}"
   - Each surface item must be a dict with `type` key. Report: "❌ <project>.surfaces[0]: missing 'type' key"
   - Valid surface types: `cli`, `api`, `web`, `mobile`, `library`, `plugin`, `sdk`
     Report: "❌ <project>.surfaces[0]: type 'cloud' not in allowed set"

Output summary:
```
✓ 2 projects validated
❌ 1 project has errors

Errors:
  ❌ xgh: missing 'surfaces'
  ❌ passcode: surfaces[1].type 'unknown' not in [cli, api, web, mobile, library, plugin, sdk]
```

If all pass: "✓ All projects valid."

## Error Handling

For any subcommand:
- If `~/.xgh/ingest.yaml` missing: "ERROR: ~/.xgh/ingest.yaml not found. Run /xgh-init first."
- If PyYAML not available: "ERROR: PyYAML not installed. Run: pip3 install pyyaml"
- If YAML parse error: "ERROR: Invalid YAML in ~/.xgh/ingest.yaml: {details}"
- If permission denied: "ERROR: Cannot write to ~/.xgh/ingest.yaml (permission denied)"
