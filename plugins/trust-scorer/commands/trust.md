---
name: crow:trust
description: >
  Show the content-detector flags raised for changes this session, grouped by
  severity. Highlights CRITICAL and HIGH findings. No trust score — pure flags.
---

When the user runs `/crow:trust`, display the detector findings for this session.

## Data Source

Read `${CLAUDE_PLUGIN_ROOT}/state/metrics.jsonl` and select the `change_flagged`
events. Each event looks like:
```json
{"event":"change_flagged","ts":"...","file":"src/auth.ts","severity":"HIGH","flags":["weak_crypto"],"type":"source_code","turn":3}
```

Take the most recent `change_flagged` event per file for the per-file view.

Optionally run `python3 ${CLAUDE_PLUGIN_ROOT}/../../shared/scripts/trust-model.py ${CLAUDE_PLUGIN_ROOT}/state/metrics.jsonl` for a JSON roll-up (severity counts, flag-type frequency, flagged files).

## Severity Map

- **CRITICAL** — `exposed_secrets`, `gutted_test`
- **HIGH** — `weak_crypto`, `wildcard_cors`
- **WARNING** — `trivial_assertions`, `very_short_file`, `debug_enabled`, `reverted`
- **clean** — no flags

## Output Format

```
## Detector Findings (most severe first)

| Severity | File | Flags | Type |
|----------|------|-------|------|
| CRITICAL | .env | exposed_secrets | config_change |
| HIGH     | src/auth.ts | weak_crypto | source_code |
| WARNING  | api.test.ts | trivial_assertions | test_change |

Distribution: 1 critical, 1 high, 1 warning
Files assessed: 12 | Files flagged: 3
```

## Rules

1. Show "No detector data yet" if there are no `change_flagged` events.
2. Sort by severity (CRITICAL → HIGH → WARNING), then by file.
3. There is NO numeric trust score, average, or Beta parameter — never invent one.
   Report only the flags the detectors actually raised.
4. Show the severity distribution (critical/high/warning counts).
5. Emphasize CRITICAL and HIGH files.
6. Clean changes (no flags) need no listing beyond the "files assessed" count.
