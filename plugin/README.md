# xgh — eXtreme Go Horse

Persistent memory and team context for AI-assisted development.

## Installation

### Full install (recommended)

Installs all components including lossless-claude MCP, hooks, and context tree:

```bash
XGH_LOCAL_PACK=. bash install.sh
```

### Lite install via Claude plugin

Lite install (assumes infra already running — once published to plugin registry):

```
/plugin install github:ipedro/xgh
```

### Per-project setup

After installing xgh, run the onboarding command in any project:

```
/xgh-init
```

This sets up the team name, context tree path, and lossless-claude collection for the project.
