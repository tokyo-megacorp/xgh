---
name: xgh:config-profile
description: Switch between xgh profiles (work/personal contexts). Invoke when changing project context. Trigger: "switch profile", "use work context", "use personal context", "show active profile", "clear profile", "use default context".
---

# xgh:config-profile — Profile Switching

Active profile stored at `~/.xgh/active-profile` (plain text filename containing just the profile name).
Empty file or missing file means no profile is active — project defaults apply.

Parse `$ARGUMENTS` to determine the requested operation and profile name, then route to the
appropriate step below.

---

## Operation: show active profile

**Triggers:** "show active profile", "which profile", "current profile", "what context am I in"

```bash
PROFILE_FILE="$HOME/.xgh/active-profile"
if [ -f "$PROFILE_FILE" ] && [ -s "$PROFILE_FILE" ]; then
  ACTIVE=$(cat "$PROFILE_FILE" | tr -d '[:space:]')
  echo "Active profile: $ACTIVE"
else
  echo "No active profile — using project defaults."
fi
```

Then read `config/project.yaml` and display the description and preference overrides for the
active profile, if the `profiles:` section exists and the profile is defined:

```python
import yaml, os, subprocess
from pathlib import Path

result = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True)
repo_root = Path(result.stdout.strip()) if result.returncode == 0 else Path('.')
proj_yaml = repo_root / 'config' / 'project.yaml'

profile_file = Path.home() / '.xgh' / 'active-profile'
active = profile_file.read_text().strip() if profile_file.exists() else ""

if not proj_yaml.exists() or not active:
    pass  # already reported above
else:
    config = yaml.safe_load(proj_yaml.read_text()) or {}
    profiles = config.get('profiles', {})
    if active in profiles:
        p = profiles[active]
        print(f"\nProfile '{active}':")
        if 'description' in p:
            print(f"  Description: {p['description']}")
        overrides = p.get('preferences', {})
        if overrides:
            print("  Preference overrides:")
            for domain, fields in overrides.items():
                if isinstance(fields, dict):
                    for k, v in fields.items():
                        print(f"    {domain}.{k} = {v}")
    else:
        print(f"\n(Profile '{active}' not defined in config/project.yaml — preferences fall through to defaults.)")
```

---

## Operation: switch to profile

**Triggers:** "switch to work profile", "use work context", "switch to personal", "activate <name> profile"

1. Extract the profile name from the arguments (e.g., "work", "personal").
2. Optionally validate that the profile exists in `config/project.yaml` under `profiles:`.
   If the profile section is absent or the name is not found, warn the user but still activate
   (the profile name is stored as-is; preferences will fall through to defaults for undefined keys).
3. Write the profile name to `~/.xgh/active-profile`:

```bash
PROFILE_NAME="<extracted_name>"
mkdir -p "$HOME/.xgh"
printf '%s' "$PROFILE_NAME" > "$HOME/.xgh/active-profile"
echo "Switched to profile: $PROFILE_NAME"
echo "Preference overrides from this profile are now active."
```

4. Display the profile description and overrides (same as "show active profile" step).

---

## Operation: clear profile / use default context

**Triggers:** "clear profile", "use default context", "no profile", "reset profile", "deactivate profile"

```bash
PROFILE_FILE="$HOME/.xgh/active-profile"
if [ -f "$PROFILE_FILE" ]; then
  rm -f "$PROFILE_FILE"
  echo "Profile cleared — using project defaults."
else
  echo "No active profile to clear."
fi
```

---

## Profile schema reference

Profiles are defined in `config/project.yaml` under a top-level `profiles:` key.
Each profile can override any subset of the `preferences:` domains.

```yaml
profiles:
  work:
    description: "Work context — internal repos, strict scheduling"
    preferences:
      pr:
        repo: company/internal-repo
        merge_method: squash
      scheduling:
        retrieve_interval: "15m"
  personal:
    description: "Personal projects — open source, relaxed scheduling"
    preferences:
      scheduling:
        retrieve_interval: "60m"
```

**Precedence order (highest to lowest):**
1. CLI override (passed directly to skill at call time)
2. Profile override (`profiles.<name>.preferences.<domain>.<field>`)
3. Branch override (`preferences.pr.branches.<branch>.<field>`)
4. Project default (`preferences.<domain>.<field>`)

The profile overlay is additive — only the fields defined in the profile are overridden.
All other fields use their project defaults.

---

## Error Handling

- If `~/.xgh/` directory does not exist: create it with `mkdir -p`.
- If `config/project.yaml` is missing: skip profile description display, proceed with file write.
- If PyYAML is not available: skip the Python description display block; still write the profile file.
- If the profile name extracted from arguments is empty: ask the user to specify a profile name.
