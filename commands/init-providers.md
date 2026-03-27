---
name: xgh-init-providers
description: Generate provider scripts from ingest.yaml for all tracked projects with github access. Run this after manually editing ingest.yaml or when providers/ is empty.
---

# /xgh-init-providers — Generate Provider Scripts from ingest.yaml

Run the `xgh:init-providers` skill to regenerate provider scripts from the current `~/.xgh/ingest.yaml`.

## Usage

```
/xgh-init-providers
```

Run when:
- `~/.xgh/user_providers/` is empty after manual edits to `ingest.yaml`
- A new project was added to `ingest.yaml` without running `/xgh-track`
- `/xgh-doctor` reports missing or stale providers

## Related Skills

- `xgh:init-providers` — the full workflow skill this command triggers
- `xgh:track` — full interactive onboarding (generates providers as part of Step 3b)
- `xgh:doctor` — Check 6 reports provider status and suggests running this command
