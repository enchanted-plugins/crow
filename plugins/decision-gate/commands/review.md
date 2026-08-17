---
name: crow:review
description: >
  Trigger a manual review of pending changes. Shows detector-flagged changes
  ordered by severity, with type-specific adversarial questions.
---

When the user runs `/crow:review`, present the changes most worth reviewing.

## Data Sources

1. Read `change_flagged` events from `${CLAUDE_PLUGIN_ROOT}/../trust-scorer/state/metrics.jsonl` — per-change detector flags and severity.
2. Read `${CLAUDE_PLUGIN_ROOT}/../change-tracker/state/changes.jsonl` for change history.
3. Read `${CLAUDE_PLUGIN_ROOT}/state/metrics.jsonl` for previous review events.

## Algorithm

1. Take the most recent `change_flagged` event per file.
2. Keep only files with severity != clean.
3. Sort by severity: CRITICAL → HIGH → WARNING.
4. Present the top 5, with type-specific adversarial questions.

There is no information-gain / entropy ordering — that required a trust
probability, which Crow no longer computes. Ordering is by severity.

## Output Format

```
## Review Queue (most severe first)

### 1. .env — CRITICAL — exposed_secrets
Type: config_change | Edits: 1
Questions:
- Does this config change expose secrets or API keys?
- Does it break environment-specific overrides?

### 2. src/auth.ts — HIGH — weak_crypto
Type: source_code | Edits: 3
Questions:
- Does this change break existing tests or a critical path?
- Was the algorithm downgrade (e.g. HS256/md5) intentional?

Summary: [N] files flagged for review
```

## Rules

1. Show "No changes flagged — nothing needs review." if no file has severity != clean.
2. Show "No detector data available" if there are no `change_flagged` events.
3. Sort by severity, then by file — never invent a numeric score.
4. Include type-specific adversarial questions for every flagged file.
5. Mark reviewed items in metrics.jsonl as `{"event": "manual_review", ...}`.
