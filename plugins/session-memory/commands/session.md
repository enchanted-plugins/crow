---
name: vigil:session
description: >
  Show the current session dashboard. Trust overview, change count,
  review decisions, and cross-session learnings.
---

When the user runs `/vigil:session`, generate a comprehensive session report.

## Data Sources

Read state from all sibling plugin directories:
- `${CLAUDE_PLUGIN_ROOT}/../change-tracker/state/changes.jsonl` — change events
- `${CLAUDE_PLUGIN_ROOT}/../change-tracker/state/metrics.jsonl` — change metrics
- `${CLAUDE_PLUGIN_ROOT}/../trust-scorer/state/trust.json` — trust state
- `${CLAUDE_PLUGIN_ROOT}/../trust-scorer/state/learnings.json` — cross-session patterns
- `${CLAUDE_PLUGIN_ROOT}/../decision-gate/state/metrics.jsonl` — review advisories
- `${CLAUDE_PLUGIN_ROOT}/state/session-graph.json` — continuity graph (if exists)

Optionally run `python3 ${CLAUDE_PLUGIN_ROOT}/../../shared/scripts/session-report.py ${CLAUDE_PLUGIN_ROOT}/..` for a formatted report.

## Output Format

```
══════════════════════════════════════
 VIGIL SESSION REPORT
══════════════════════════════════════

 Trust:    avg 0.62 | 4 high, 3 medium, 2 low, 1 critical
 Changes:  15 tracked | 10 scored | 3 reviewed

 ── Trust Distribution ─────────────
 High (>0.8):        4 files
 Medium:             3 files
 Low (<0.4):         2 files
 Critical (<0.2):    1 file

 ── Changes by Type ────────────────
 source_code            8
 test_change            3
 config_change          2
 documentation          2

 ── Riskiest Files ─────────────────
 0.18  .env (config_change)
 0.35  src/db.ts (schema_change)

 ── Review Advisories ──────────────
 Total advisories: 3
 Most reviewed: src/auth.ts (2 advisories)

 ── Cross-Session Patterns ─────────
 Sessions recorded: 4
 Avg trust: 0.64
 Alert: chronic:low_trust:config_change

 Methodology: Bayesian Beta-Bernoulli trust.
══════════════════════════════════════
```

## Rules

1. Show "No data yet" if all state files are empty or missing.
2. Trust overview is FIRST. Changes by type is SECOND.
3. Never fabricate numbers — only show what state files contain.
4. Always show the methodology line.
5. Use `grep` with pre-filter on JSONL files — never `jq -s` on full files.
6. Show cross-session learnings only if learnings.json exists and has data.
