#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }

assert_file_exists "providers/_template/spec.md"
assert_contains "providers/_template/spec.md" "provider.yaml"
assert_contains "providers/_template/spec.md" "fetch.sh"
assert_contains "providers/_template/spec.md" "cursor"
assert_contains "providers/_template/spec.md" "tokens.env"
assert_contains "providers/_template/spec.md" "inbox"
assert_contains "providers/_template/spec.md" "urgency_keywords"

# GitHub provider
assert_file_exists "providers/github/spec.md"
assert_contains "providers/github/spec.md" "gh api"
assert_contains "providers/github/spec.md" "notifications"
assert_contains "providers/github/spec.md" "pull_requests"
assert_contains "providers/github/spec.md" "cursor"
assert_contains "providers/github/spec.md" "provider.yaml"
assert_contains "providers/github/spec.md" "fetch.sh"

# Slack provider
assert_file_exists "providers/slack/spec.md"
assert_contains "providers/slack/spec.md" "SLACK_BOT_TOKEN"
assert_contains "providers/slack/spec.md" "conversations.history"
assert_contains "providers/slack/spec.md" "cursor"
assert_contains "providers/slack/spec.md" "fetch.sh"

# Jira provider
assert_file_exists "providers/jira/spec.md"
assert_contains "providers/jira/spec.md" "JIRA_BASE_URL"
assert_contains "providers/jira/spec.md" "JIRA_EMAIL"
assert_contains "providers/jira/spec.md" "JIRA_API_TOKEN"
assert_contains "providers/jira/spec.md" "rest/api/3/search"

# Confluence provider
assert_file_exists "providers/confluence/spec.md"
assert_contains "providers/confluence/spec.md" "JIRA_BASE_URL"
assert_contains "providers/confluence/spec.md" "rest/api/content/search"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
