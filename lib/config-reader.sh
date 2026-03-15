#!/usr/bin/env bash
# lib/config-reader.sh — Read values from ~/.xgh/ingest.yaml
# Usage: source lib/config-reader.sh
#        xgh_config_get "budget.daily_token_cap" [default_value]

xgh_config_get() {
  local key="$1"
  local default="${2:-}"
  local config="${HOME}/.xgh/ingest.yaml"
  [ -f "$config" ] || { echo "$default"; return 1; }
  if ! python3 -c "import yaml" 2>/dev/null; then echo "$default"; return 1; fi
  python3 - "$config" "$key" "$default" << 'PYEOF'
import sys, yaml
config_path, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(config_path) as f:
        data = yaml.safe_load(f) or {}
    val = data
    for k in key.split('.'):
        val = val[k] if isinstance(val, dict) else None
        if val is None:
            break
    print(val if val is not None else default)
except Exception:
    print(default)
PYEOF
}
