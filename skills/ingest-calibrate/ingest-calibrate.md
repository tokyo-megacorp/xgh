---
name: xgh:ingest-calibrate
description: >
  Calibrate the dedup similarity threshold against real data. Pulls sample pairs from
  Cipher workspace memory, evaluates them for semantic duplication, computes F1 scores
  at multiple thresholds, and offers to update analyzer.dedup_threshold in ingest.yaml.
type: flexible
triggers:
  - when the user runs /xgh-calibrate
  - when the user says "calibrate dedup", "tune threshold", "calibrate memory"
mcp_dependencies:
  - mcp__cipher__cipher_memory_search
---

# xgh:ingest-calibrate — Dedup Threshold Calibration

Modes: interactive (default), headless (`--auto`), comparison (`--compare`).

## Interactive mode (default)

1. **Sample pairs**: Use `cipher_memory_search` with diverse queries to gather N memories (configurable via `calibration.sample_size`, default 50). Form random pairs from the results.

2. **For each pair**, show side by side:
   ```
   Pair 14/50 — similarity: 0.87

   A: "PIN entry now requires biometric fallback after 3 failed attempts"
   B: "Biometric authentication required as fallback when PIN fails 3 times"

   Duplicate? [y/n/skip]:
   ```

3. **Collect judgments**: Track (similarity_score, is_duplicate) tuples.

4. **Compute threshold analysis**: For thresholds 0.70–0.95 in steps of 0.05, compute precision, recall, and F1 against user judgments.

5. **Recommend** the threshold with highest F1.

6. **Offer update**:
   ```
   Optimal threshold: 0.85 (F1: 0.86)
   Update analyzer.dedup_threshold in ~/.xgh/ingest.yaml? [y/n]:
   ```

7. **Write calibration report** to `~/.xgh/calibration/YYYY-MM-DD.md`:
   ```markdown
   ---
   date: 2026-03-15
   type: calibration
   mode: interactive
   sample_size: 50
   optimal_threshold: 0.85
   ---
   # Dedup Calibration Report
   ## Results
   - Pairs evaluated: 50
   - Duplicates: 18, Not: 29, Skipped: 3
   ## Threshold Analysis
   | Threshold | Precision | Recall | F1 |
   |---|---|---|---|
   | 0.80 | 0.72 | 0.94 | 0.82 |
   | 0.85 | 0.89 | 0.83 | 0.86 |
   | 0.90 | 0.94 | 0.72 | 0.82 |
   ## Recommendation
   Optimal: **0.85** (F1: 0.86)
   ```

8. Update `calibration.last_run` and `calibration.last_threshold` in `ingest.yaml`.

## Headless mode (--auto)

Same as interactive, but use a Claude reasoning step to judge each pair ("Are these two memories describing the same fact?"). Only auto-update `ingest.yaml` if AI judgment confidence > `calibration.auto_confidence_threshold` (default 0.9).

## Comparison mode (--compare)

Run headless calibration first, then run interactive on the same pairs. Show agreement rate between AI and human judgments at the end. This validates whether headless mode is reliable for future auto-runs.
