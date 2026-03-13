#!/usr/bin/env bash
# xgh UserPromptSubmit hook
# Detects prompt intent and injects decision table with tool hints.
# Output: Structured JSON with promptIntent, requiredActions, toolHints
set -euo pipefail

python3 << 'PYEOF'
import json, os, re

prompt = os.environ.get("PROMPT", "")

# Intent detection via regex
code_pattern = re.compile(
    r"\b(implement|refactor|fix|build|code|write|change|feature|bug)\b",
    re.IGNORECASE
)

if code_pattern.search(prompt):
    intent = "code-change"
else:
    intent = "general"

required_actions = [
    "Run cipher_memory_search before writing code.",
    "Run cipher_extract_and_operate_memory after significant work.",
    "Store architectural rationale with cipher_store_reasoning_memory."
]

tool_hints = [
    "cipher_memory_search",
    "cipher_extract_and_operate_memory",
    "cipher_store_reasoning_memory"
]

output = {
    "result": "xgh: prompt-submit decision table injected",
    "promptIntent": intent,
    "requiredActions": required_actions,
    "toolHints": tool_hints
}

print(json.dumps(output))
PYEOF
exit 0
