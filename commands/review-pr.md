---
name: review-pr
description: "Run a deep multi-persona code review on one or more PRs — 4 parallel personas, 2 rounds of cross-pollination"
usage: "/xgh-review-pr [PR numbers] [--rounds N]"
aliases: ["rpr"]
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh review-pr`.

# /xgh-review-pr

Run the `xgh:review-pr` skill to perform a deep multi-persona code review.

## Usage

```
/xgh-review-pr 114 115          # review PRs #114 and #115
/xgh-review-pr                  # auto-detect open PRs by current user
/xgh-review-pr 114 --rounds 1   # single round only
```
