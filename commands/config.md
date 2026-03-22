---
name: xgh-config
description: "Structured editor for ~/.xgh/ingest.yaml — show, set, add-project, remove-project, validate"
allowed-tools: [Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion]
---

# /xgh-config — Manifest Editor

Structured interface for reading and writing `~/.xgh/ingest.yaml`.

## Usage

```
/xgh-config show [section]           # Display full manifest or a dot-path section
/xgh-config set <path> <value>       # Set a value at dot-path (e.g., projects.xgh.stack shell)
/xgh-config add-project <name>       # Interactive: add a new project with github, stack, surfaces
/xgh-config remove-project <name>    # Remove a project (confirm first)
/xgh-config validate                 # Validate all projects for required fields and type correctness
```

## Subcommands

### show [section]

Display the full manifest or a specific section using dot-path notation.

```
/xgh-config show
/xgh-config show projects
/xgh-config show projects.xgh
/xgh-config show projects.xgh.stack
```

### set <path> <value>

Set a configuration value using dot-path notation. Validates type based on context.

```
/xgh-config set projects.xgh.stack shell
/xgh-config set projects.xgh.surfaces "[{\"type\": \"cli\"}, {\"type\": \"plugin\"}]"
```

### add-project <name>

Interactive prompt to add a new project. Asks for:
- GitHub repository (org/repo format)
- Stack type: shell, typescript, swift, kotlin, go, rust, python, generic
- Surfaces (list of exposed interfaces): cli, api, web, mobile, library, plugin, sdk

### remove-project <name>

Remove a project after confirming.

### validate

Check all projects for:
- Required fields: `stack`, `surfaces`, `github`
- Type correctness:
  - `stack` must be a string
  - `surfaces` must be a list of objects, each with a `type` key
- Report missing fields and type mismatches
