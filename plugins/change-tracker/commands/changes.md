---
name: raven:changes
description: >
  Show all tracked changes in this session, grouped by type and file.
  Includes semantic classification and cluster information.
---

When the user runs `/raven:changes`, generate a change summary by reading state data.

## Data Source

Read `${CLAUDE_PLUGIN_ROOT}/state/changes.jsonl`. Each line is a JSON object with:
- `ts`: timestamp
- `file`: file path
- `type`: change classification (source_code, config_change, test_change, documentation, schema_change, dependency_change)
- `changed`: boolean (true if file content actually changed)
- `cluster_id`: co-location cluster identifier
- `tool`: the tool that made the change (Write, Edit, MultiEdit)
- `turn`: session turn number

## Output Format

```
## Session Changes ([N] total)

### source_code ([N] files)
- src/auth.ts (3 edits, last: 14:23)
- src/routes.ts (1 edit, last: 14:25)
  [cluster: co-located with src/auth.ts]

### config_change ([N] files)
- .env (1 edit, last: 14:30)

### test_change ([N] files)
- tests/auth.test.ts (2 edits, last: 14:28)

Summary: [N] files | [N] types | [N] clusters
```

## Rules

1. Show "No changes tracked yet" if changes.jsonl is empty or missing.
2. Group by change type, then list files within each type.
3. Show edit count and last timestamp per file.
4. Show cluster relationships where cluster_id matches across files.
5. Use `grep` with pre-filter — never slurp entire file with `jq -s`.
6. Sort types by count (most changes first).
