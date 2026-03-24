# Project Preferences Reference

Skills can read `config/project.yaml` at dispatch time to pick up project-level defaults
without relying on AGENTS.md.

## Reading preferences (Python, stdlib only)

```python
import yaml, os
prefs = {}
if os.path.exists("config/project.yaml"):
    with open("config/project.yaml") as f:
        cfg = yaml.safe_load(f) or {}
    prefs = cfg.get("preferences", {})
```

## Key preference blocks

| Block | Keys | Used by |
|-------|------|---------|
| `dispatch` | `default_agent`, `fallback_agent`, `exec_effort`, `review_effort` | `/xgh-dispatch` cold-start defaults |
| `pair_programming` | `enabled`, `tool`, `effort`, `phases` | pair-programming skills |
| `superpowers` | `implementation_model`, `review_model`, `effort` | superpowers dispatch |
| `design` | `model`, `effort` | `/xgh-design` |
| `agents` | `default_model` | agent frontmatter with `model: inherit` |

## Priority order

User override at call time → profile data (`model-profiles.yaml`) → **project preferences** → CLI defaults

Skills MUST respect this order. Never let project preferences override an explicit user flag.
