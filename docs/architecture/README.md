# Crow Architecture

> Auto-generated from codebase by `generate.py`. Run `python docs/architecture/generate.py` to regenerate.

## Interactive Explorer

Open [index.html](index.html) in a browser to explore the architecture interactively with tabbed Mermaid diagrams and plugin component cards.

## At a Glance

**4 plugins. 6 algorithms (H1–H6). 3 hook phases. 15 tests.**

Change-trust-review-learn loop: observe every write, score trust, surface questions on low-trust edits, and persist a continuity graph across compactions.

## Diagrams

| Diagram | File | Description |
|---------|------|-------------|
| High Level | [highlevel.mmd](highlevel.mmd) | 4 plugins connected to Claude Code with hook phases |
| Session Lifecycle | [lifecycle.mmd](lifecycle.mmd) | PreToolUse → Edit → PostToolUse → PreCompact cycle |
| Data Flow | [dataflow.mmd](dataflow.mmd) | Change events → trust scores → session graph |
| Hook Bindings | [hooks.mmd](hooks.mmd) | Hook binding map with matchers and timeouts per plugin |

## Plugin Summary

| Plugin | Hook Phase | Matcher | Timeout | Algorithms |
|--------|-----------|---------|---------|------------|
| decision-gate | PostToolUse | Write/Edit/MultiEdit | 10s | H3 (Info-Gain), H5 (Adversarial) |
| change-tracker | PostToolUse | Write/Edit/MultiEdit | 15s | H1 (Semantic Diff) |
| trust-scorer | PostToolUse | Write/Edit/MultiEdit | 15s | H2 (Bayesian Trust) |
| session-memory | PreCompact | — | 30s | H4 (Continuity), H6 (Learning) |

## Algorithms (H1–H6)

| Code | Name | Where |
|------|------|-------|
| H1 | Semantic Diff Analysis | `shared/scripts/diff-analyzer.py` |
| H2 | Bayesian Trust Scoring | `plugins/trust-scorer/hooks/post-tool-use/score-change.sh` |
| H3 | Information-Gain Ordering | `plugins/decision-gate/hooks/post-tool-use/gate-change.sh` |
| H4 | Session Continuity Graph | `plugins/session-memory/hooks/pre-compact/save-session.sh` |
| H5 | Adversarial Self-Review | `plugins/decision-gate/hooks/post-tool-use/gate-change.sh` |
| H6 | Exponential Strategy Averaging (EMA Accumulation) | `shared/scripts/learnings.py` |

Full derivations: [docs/science/README.md](../science/README.md).

## Execution Order

```
1. Write/Edit/MultiEdit tool executes
2. PostToolUse  → decision-gate: H3 IG-ranking + H5 adversarial questions on low-trust writes (reads fresh trust)
3. PostToolUse  → change-tracker: H1 semantic diff, hunk classification, cluster grouping
4. PostToolUse  → trust-scorer: H2 Bayesian posterior update + red-flag detection
5. PreCompact   → session-memory: H4 continuity graph + H6 Exponential Strategy Averaging persistence
```

## State Files

| Plugin | Files | Purpose |
|--------|-------|---------|
| change-tracker | `changes.jsonl`, `metrics.jsonl` | Per-change hunks + cluster ids |
| trust-scorer | `trust.json`, `metrics.jsonl` | Beta posteriors per file |
| decision-gate | `metrics.jsonl` | Advisory events, cooldown state |
| session-memory | `session-graph.json`, `session-summary.md`, `metrics.jsonl` | Cross-session continuity |
| shared | `learnings.json` | EMA rates per change type |

## Test Coverage

15 tests across all plugins + shared utilities:

```
tests/
├── change-tracker/    2 tests (classification, clustering)
├── decision-gate/     3 tests (IG ordering, adversarial questions, cooldown)
├── session-memory/    2 tests (graph assembly, markdown export)
├── trust-scorer/      3 tests (Bayesian update, red-flag detection, priors)
├── shared/            2 tests (sanitize paths, JSON validation)
├── demo.sh            Interactive session walk-through
├── integration-test.sh Full pipeline test (change → trust → gate → graph)
└── run-all.sh         Master runner
```

## Trust Thresholds

| Range | Label | Behavior |
|-------|-------|----------|
| ≥ 0.80 | HIGH | Pass through; light acknowledgment |
| 0.40 – 0.80 | MEDIUM | Log with reason codes |
| 0.20 – 0.40 | LOW | Surface adversarial questions on next PreToolUse |
| < 0.20 | CRITICAL | Emphasize in session summary, flag for review |
