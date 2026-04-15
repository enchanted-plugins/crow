---
name: vigil:trust
description: >
  Show trust scores for all tracked files. Highlights low-trust
  and critical-trust files. Shows Bayesian parameters.
---

When the user runs `/vigil:trust`, display the current trust state.

## Data Source

Read `${CLAUDE_PLUGIN_ROOT}/state/trust.json`. This is a JSON object keyed by file path:
```json
{
  "src/auth.ts": {"alpha": 3.2, "beta": 1.8, "score": 0.64, "type": "source_code", "ts": "..."}
}
```

Optionally run `python3 ${CLAUDE_PLUGIN_ROOT}/../../shared/scripts/trust-model.py ${CLAUDE_PLUGIN_ROOT}/state/trust.json` for a distribution summary.

## Output Format

```
## Trust Scores (riskiest first)

| Score | File | Type | Prior |
|-------|------|------|-------|
| 0.31  | .env | config_change | Beta(2.3, 3.7) |
| 0.45  | src/db.ts | schema_change | Beta(3.1, 3.8) |
| 0.64  | src/auth.ts | source_code | Beta(3.2, 1.8) |
| 0.85  | README.md | documentation | Beta(4.9, 0.9) |

Distribution: 1 critical, 1 low, 1 medium, 1 high
Average trust: 0.56
```

## Rules

1. Show "No trust data yet" if trust.json is empty or missing.
2. Sort by trust score ascending (riskiest first).
3. Always show Beta parameters (alpha, beta) — transparency matters.
4. Show distribution summary (critical/low/medium/high counts).
5. Show average trust score.
6. Highlight critical (<0.2) and low (<0.4) files with emphasis.
