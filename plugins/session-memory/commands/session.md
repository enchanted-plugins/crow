---
name: crow:session
description: >
  Show the current session dashboard. Severity overview, change count,
  review decisions, and cross-session learnings.
---

When the user runs `/crow:session`, generate a comprehensive session report.

## Data Sources

Read state from all sibling plugin directories:
- `${CLAUDE_PLUGIN_ROOT}/../change-tracker/state/changes.jsonl` — change events
- `${CLAUDE_PLUGIN_ROOT}/../change-tracker/state/metrics.jsonl` — change metrics
- `${CLAUDE_PLUGIN_ROOT}/../trust-scorer/state/metrics.jsonl` — `change_flagged` detector events
- `${CLAUDE_PLUGIN_ROOT}/../trust-scorer/state/learnings.json` — cross-session patterns
- `${CLAUDE_PLUGIN_ROOT}/../decision-gate/state/metrics.jsonl` — review advisories
- `${CLAUDE_PLUGIN_ROOT}/state/session-graph.json` — continuity graph (if exists)

Optionally run `python3 ${CLAUDE_PLUGIN_ROOT}/../../shared/scripts/session-report.py ${CLAUDE_PLUGIN_ROOT}/..` for a formatted report.

## Output Format

```
══════════════════════════════════════
 CROW SESSION REPORT
══════════════════════════════════════

 Flags:    1 critical, 2 high, 3 warning (10 files assessed)
 Changes:  15 tracked | 10 assessed | 3 reviewed

 ── Severity Distribution ──────────
 CRITICAL:   1 files
 HIGH:       2 files
 WARNING:    3 files
 clean:      4 files

 ── Changes by Type ────────────────
 source_code            8
 test_change            3
 config_change          2
 documentation          2

 ── Flagged Files ──────────────────
 CRITICAL  .env (exposed_secrets)
 HIGH      src/auth.ts (weak_crypto)

 ── Review Advisories ──────────────
 Total advisories: 3
 Most reviewed: src/auth.ts (2 advisories)

 ── Cross-Session Patterns ─────────
 Sessions recorded: 4
 Avg flag rate: 0.22
 Alert: chronic:high_flag_rate:config_change

 Methodology: stateless content-detector suite (flags + severity, no score).
══════════════════════════════════════
```

## Rules

1. Show "No data yet" if all state files are empty or missing.
2. Severity overview is FIRST. Changes by type is SECOND.
3. Never fabricate numbers — only show what state files contain. There is no
   numeric trust score; report severities and flags.
4. Always show the methodology line.
5. Use `grep` with pre-filter on JSONL files — never `jq -s` on full files.
6. Show cross-session learnings only if learnings.json exists and has data.
