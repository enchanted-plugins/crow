---
name: raven:review
description: >
  Trigger a manual review of pending changes. Shows information-gain
  ranked list of changes that should be reviewed, with adversarial questions.
---

When the user runs `/raven:review`, present the highest-value changes to review.

## Data Sources

1. Read `${CLAUDE_PLUGIN_ROOT}/../trust-scorer/state/trust.json` for per-file trust scores.
2. Read `${CLAUDE_PLUGIN_ROOT}/../change-tracker/state/changes.jsonl` for change history.
3. Read `${CLAUDE_PLUGIN_ROOT}/state/metrics.jsonl` for previous review events.

## Algorithm

For each file in trust.json with trust < 0.8:
1. Compute information gain (binary entropy of trust score):
   - IG = -p*log2(p) - (1-p)*log2(1-p), where p = trust score
   - Maximum IG at trust = 0.5 (most uncertain)
2. Sort by IG descending (review most uncertain files first)
3. Present top 5

## Output Format

```
## Review Queue (by information gain)

### 1. src/auth.ts — trust: 0.45, IG: 0.99
Type: source_code | Edits: 3
Questions:
- Does this change break existing authentication flows?
- Are all call sites updated to match the new signature?

### 2. .env — trust: 0.31, IG: 0.89
Type: config_change | Edits: 1
Questions:
- Does this config change expose any secrets or API keys?
- Does it break environment-specific overrides?

### 3. ...

Summary: [N] files need review | Avg trust of review queue: [score]
```

## Rules

1. Show "All changes above trust threshold — no review needed" if all files have trust >= 0.8.
2. Show "No trust data available" if trust.json is missing or empty.
3. Always sort by IG, not by trust score or file path.
4. Include type-specific adversarial questions for files with trust < 0.4.
5. Mark reviewed items in metrics.jsonl as `{"event": "manual_review", ...}`.
