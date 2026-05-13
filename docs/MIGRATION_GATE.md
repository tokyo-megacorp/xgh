# xgh → katsuragi-corp Migration Gate

## Status: PENDING

Gate criteria (ALL must be true before migrating):

- [ ] xgh has had no major architectural change for 30 consecutive days
- [ ] xgh has a stable v1 release (or explicit "architecture frozen" milestone)
- [ ] All CI/CD workflows, webhooks, GitHub Apps, and secrets inventoried in xgh/docs/infra.md
- [ ] katsuragi-corp has a published org profile README
- [ ] xgh:transfer-repo skill is built and tested (claudinho#255)
- [ ] Pedro has reviewed this doc and signed off

## Last Reviewed

2026-04-02 — xgh on 3rd architectural pivot, gate NOT passed.

## How to Pass

Check each box above, update "Last Reviewed" date, open a PR to this file. Merge = migration begins.

## Non-goal

This document only defines the migration gate. It does not start, automate, or authorize the xgh repository migration by itself.
