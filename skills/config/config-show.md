---
name: xgh:config-show
description: "This skill should be used when the user runs /xgh-config show or asks to 'show preferences', 'show project config', 'what are the current preferences', 'show resolved config'. Displays all resolved preferences for the current branch from config/project.yaml, with source attribution (project default vs branch override) and a pending preferences count."
---

# xgh:config-show — Display Resolved Project Preferences

## Trigger

Runs when user executes `/xgh-config show`.

## Steps

### 1. Locate project.yaml

```python
import yaml, subprocess, os, sys
from pathlib import Path

# Find repo root
result = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True)
repo_root = Path(result.stdout.strip()) if result.returncode == 0 else Path('.')
proj_yaml_path = repo_root / 'config' / 'project.yaml'

if not proj_yaml_path.exists():
    print("No project.yaml found. Run /xgh-init to create one.")
    sys.exit(0)

with open(proj_yaml_path) as f:
    config = yaml.safe_load(f) or {}

prefs = config.get('preferences', {})
```

### 2. Detect current branch

```bash
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
```

Pass `CURRENT_BRANCH` into the Python script as a variable.

### 3. Resolve all domains

Use this Python logic to resolve values and attribute their source. For each domain, iterate its fields and apply cascade rules using `lib/config-reader.sh`-compatible logic:

```python
def get_source(domain, field, branch, config):
    """Return (value, source_label) for a preference field."""
    prefs = config.get('preferences', {})
    domain_prefs = prefs.get(domain, {})

    # Check branch override (only for pr domain)
    if domain == 'pr' and branch:
        branch_override = domain_prefs.get('branches', {}).get(branch, {}).get(field)
        if branch_override is not None:
            return (branch_override, f"branch override ({branch})")

    # Project default
    val = domain_prefs.get(field)
    if val is not None:
        return (val, "project default")

    return (None, None)
```

### 4. Output format

Print the following markdown table structure. Only show domains that have at least one configured field. Skip the `branches` sub-key when iterating `pr` fields (it is metadata, not a preference field).

**Header:**

```
## xgh Project Preferences

**Project:** {project_name} | **Branch:** {current_branch}
```

Where `project_name` comes from `config.get('name', 'xgh')`.

**Per domain table** — use these domain display names:

| Domain key | Display name |
|---|---|
| `pr` | PR Workflow |
| `dispatch` | Dispatch |
| `superpowers` | Superpowers |
| `design` | Design |
| `agents` | Agents |
| `pair_programming` | Pair Programming |

For each domain with values, print:

```markdown
### {Display Name}
| Field | Value | Source |
|-------|-------|--------|
| {field} | {value} | {source} |
```

For `pr` domain: after the main table, if the current branch has entries under `preferences.pr.branches.<current_branch>`, append a **Branch Override** note:

```
> **Branch override active for `{current_branch}`:** {field}={value}, ...
```

**Source column values:**
- `"project default"` — value comes from `preferences.<domain>.<field>`
- `"branch override ({branch})"` — value comes from `preferences.pr.branches.<branch>.<field>`
- `"CLI override"` — (future; not applicable in this read-only skill)
- `"local probe"` — (future; not applicable in this read-only skill)

### 5. Pending preferences count

Check for any `.xgh/pending-preferences-*.yaml` files in the repo root:

```python
pending_files = list((repo_root / '.xgh').glob('pending-preferences-*.yaml'))
total_pending = 0
for f in pending_files:
    with open(f) as pf:
        data = yaml.safe_load(pf) or {}
    total_pending += len(data.get('pending', []))
```

Print at the end:

```markdown
### Pending Preferences
{count} pending preference(s). Run /xgh-save-preferences to apply.
```

Or if zero:

```markdown
### Pending Preferences
No pending preferences.
```

## Error Handling

- **Missing project.yaml**: Print `No project.yaml found. Run /xgh-init to create one.` and stop.
- **PyYAML not available**: Print `ERROR: PyYAML not installed. Run: pip3 install pyyaml` and stop.
- **Empty preferences block**: Print header + `No preferences configured yet.`
- **Git not available**: Use `"unknown"` as branch name.

## Full Example Output

```
## xgh Project Preferences

**Project:** xgh | **Branch:** develop

### PR Workflow
| Field | Value | Source |
|-------|-------|--------|
| provider | github | project default |
| repo | tokyo-megacorp/xgh | project default |
| reviewer | copilot-pull-request-reviewer[bot] | project default |
| reviewer_comment_author | Copilot | project default |
| review_on_push | true | project default |
| merge_method | squash | branch override (develop) |
| auto_merge | true | project default |

> **Branch override active for `develop`:** merge_method=squash

### Dispatch
| Field | Value | Source |
|-------|-------|--------|
| default_agent | xgh:dispatch | project default |
| fallback_agent | xgh:gemini | project default |
| exec_effort | high | project default |
| review_effort | normal | project default |

### Superpowers
| Field | Value | Source |
|-------|-------|--------|
| implementation_model | sonnet | project default |
| review_model | opus | project default |
| effort | normal | project default |

### Design
| Field | Value | Source |
|-------|-------|--------|
| model | opus | project default |
| effort | max | project default |

### Agents
| Field | Value | Source |
|-------|-------|--------|
| default_model | sonnet | project default |

### Pair Programming
| Field | Value | Source |
|-------|-------|--------|
| enabled | true | project default |
| tool | xgh:dispatch | project default |
| effort | high | project default |
| phases | [design, per_task] | project default |

### Pending Preferences
No pending preferences.
```

## Implementation Notes

- Source `lib/config-reader.sh` is available for shell callers; this skill uses equivalent Python logic for inline execution.
- The `branches` key under `pr` is structural metadata — never render it as a preference field row.
- Boolean values should render as `true`/`false` (lowercase), list values as comma-separated or YAML inline.
- Domain order in output: `pr`, `dispatch`, `superpowers`, `design`, `agents`, `pair_programming` — then any additional domains found in the file.
