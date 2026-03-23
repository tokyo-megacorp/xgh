# Project Resolution Protocol

This reference documents the standard procedure for resolving the active project from the xgh configuration.

## Overview

The Project Resolution protocol reads the git remote URL of the current directory and matches it against configured projects in `~/.xgh/ingest.yaml`. It returns the project name for use in subsequent skill steps, or reports an error if no match is found.

## Implementation

Get the git remote of the current directory:

```bash
git -C . remote get-url origin 2>/dev/null || git -C . remote get-url upstream 2>/dev/null || true
```

Match the remote URL against `projects.<name>.github` in `~/.xgh/ingest.yaml`:

```bash
python3 -c "
import sys, os
try:
    import yaml
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'pyyaml', '-q'])
    import yaml

remote = sys.argv[1].strip()
if not remote:
    print('NO_REMOTE')
    sys.exit(0)
path = os.path.expanduser('~/.xgh/ingest.yaml')
try:
    data = yaml.safe_load(open(path)) or {}
except FileNotFoundError:
    print('NO_INGEST_YAML')
    sys.exit(0)
except (PermissionError, OSError):
    print('NO_INGEST_UNREADABLE')
    sys.exit(0)
except yaml.YAMLError:
    print('NO_INGEST_PARSE_ERROR')
    sys.exit(0)

projects = data.get('projects', {})
for name, cfg in projects.items():
    github_entries = cfg.get('github', [])
    if isinstance(github_entries, str):
        github_entries = [github_entries]
    for gh in github_entries:
        if gh in remote or remote in gh:
            print(name)
            sys.exit(0)

print('NO_MATCH')
" "<remote-url>"
```

## Usage

1. Capture the git remote URL from the first command
2. Pass it to the Python script as the `<remote-url>` argument
3. Parse the output:
   - **Valid project name**: Resolution succeeded. Store this as `<repo-name>` for use in subsequent steps.
   - **`NO_REMOTE`**: No git remote was found in the current directory.
   - **`NO_INGEST_YAML`**: The `~/.xgh/ingest.yaml` file does not exist.
   - **`NO_INGEST_UNREADABLE`**: The file exists but cannot be read (permissions or OS error).
   - **`NO_INGEST_PARSE_ERROR`**: The file exists but contains invalid YAML.
   - **`NO_MATCH`**: The remote URL was not found in any configured project's github entries.

## Error Handling

If output is `NO_REMOTE`:
- Stop execution and tell the user: "No git remote found. Make sure you're in a git repo with an `origin` or `upstream` remote."

If output is `NO_INGEST_YAML`:
- Stop execution and tell the user: "No ingest config found. Run `/xgh-init` first."

If output is `NO_INGEST_UNREADABLE`:
- Stop execution and tell the user: "Cannot read `~/.xgh/ingest.yaml`. Check file permissions."

If output is `NO_INGEST_PARSE_ERROR`:
- Stop execution and tell the user: "`~/.xgh/ingest.yaml` is not valid YAML. Fix the syntax and retry."

If output is `NO_MATCH`:
- Stop execution and tell the user: "No project config found for this repo. Run `/xgh-config add-project` to register it."

## Example

```bash
# Step 1: Get remote URL
REMOTE=$(git -C . remote get-url origin 2>/dev/null || git -C . remote get-url upstream 2>/dev/null || true)

# Step 2: Resolve project
PROJECT=$(python3 -c "..." "$REMOTE")

# Step 3: Check result
if [ "$PROJECT" = "NO_REMOTE" ]; then
  echo "No git remote found. Make sure you're in a git repo with an origin or upstream remote."
  exit 1
elif [ "$PROJECT" = "NO_INGEST_YAML" ]; then
  echo "No ingest config found. Run \`/xgh-init\` first."
  exit 1
elif [ "$PROJECT" = "NO_INGEST_UNREADABLE" ]; then
  echo "Cannot read ~/.xgh/ingest.yaml. Check file permissions."
  exit 1
elif [ "$PROJECT" = "NO_INGEST_PARSE_ERROR" ]; then
  echo "~/.xgh/ingest.yaml is not valid YAML. Fix the syntax and retry."
  exit 1
elif [ "$PROJECT" = "NO_MATCH" ]; then
  echo "No project config found for this repo. Run \`/xgh-config add-project\` to register it."
  exit 1
fi

# Step 4: Use project name
echo "Resolved project: $PROJECT"
```
