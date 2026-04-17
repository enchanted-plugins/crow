# Hornet — Agent Contract

Audience: Claude. Hornet watches file changes, scores each for trust with a Bayesian model, orders reviews by information gain, and preserves the decision graph across compaction.

## Shared behavioral modules

These apply to every skill in every plugin. Load once; do not re-derive.

- @shared/conduct/discipline.md — coding conduct: think-first, simplicity, surgical edits, goal-driven loops
- @shared/conduct/context.md — attention-budget hygiene, U-curve placement, checkpoint protocol
- @shared/conduct/verification.md — independent checks, baseline snapshots, dry-run for destructive ops
- @shared/conduct/delegation.md — subagent contracts, tool whitelisting, parallel vs. serial rules
- @shared/conduct/failure-modes.md — 14-code taxonomy for accumulated-learning logs
- @shared/conduct/tool-use.md — tool-choice hygiene, error payload contract, parallel-dispatch rules
- @shared/conduct/skill-authoring.md — SKILL.md frontmatter discipline, discovery test
- @shared/conduct/hooks.md — advisory-only hooks, injection over denial, fail-open
- @shared/conduct/precedent.md — log self-observed failures to `state/precedent-log.md`; consult before risky steps

When a module conflicts with a plugin-local instruction, the plugin wins — but log the override.

## Lifecycle

| Plugin | Hook | Purpose |
|--------|------|---------|
| decision-gate | PreToolUse (Write\|Edit\|MultiEdit) | Advisory gate; adversarial questions for trust < 0.4 (V3, V5) |
| change-tracker | PostToolUse (Write\|Edit\|MultiEdit) | Semantic diff compression + classification (V1) |
| trust-scorer | PostToolUse (Write\|Edit\|MultiEdit) | Beta-Bernoulli posterior update (V2) |
| session-memory | PreCompact | Continuity graph + EMA learnings (V4, V6) |

## Algorithms

V1 Semantic Diff Compression · V2 Bayesian Trust Scoring · V3 Information-Gain Ordering · V4 Session Continuity Graph · V5 Adversarial Self-Review · V6 Gauss Learning. Derivations in `README.md` § *The Science Behind Hornet*.

## Behavioral contracts

Markers: **[H]** hook-enforced · **[A]** advisory.

1. **[H] IMPORTANT — Acknowledge the `[Hornet]` stderr.** Name what was flagged, its trust score, and the change type. Silence after an advisory is a contract violation.
2. **[A] YOU MUST pause at trust < 0.4.** Explain what you changed and why. Do not continue writing the same file without addressing the flag. If decision-gate (V5) emitted adversarial questions, answer them specifically — they're generated from the diff, not boilerplate.
3. **[A] YOU MUST stop at trust < 0.2.** Surface to the developer: "Hornet flagged this as critical. Here's what I changed and what could go wrong." Do not resume until acknowledged.
4. **[A] Respect IG ordering.** `IG(trust) = -p log p - (1-p) log(1-p)` peaks at trust = 0.5 — uncertain changes get reviewed first, not decided ones. When surfacing a review queue, lead with the riskiest (lowest trust), not the newest.
5. **[A] ESCALATE on override.** If the developer waives a flag, note it honestly. V6 Gauss Learning adjusts the prior for similar future changes based on real overrides; silent dismissals poison the EMA.
6. **[A] Restore before resume.** After compaction, read `plugins/session-memory/state/session-summary.md` and brief: "Last session: N changes, M low-trust flagged, K advisories." Then resume.

## Trust bands (V2)

| Score | Band | Action |
|-------|------|--------|
| ≥ 0.8 | high | No review needed |
| 0.4–0.8 | moderate | Optional review; mention to developer |
| 0.2–0.4 | low | Pause; explain change; answer adversarial questions |
| < 0.2 | critical | Stop; surface to developer |

Priors: all files start at Beta(2, 2), mean 0.5. Docs/tests push trust up; config/schema push it down. Reverts halve the likelihood. Sensitive files (.env, secrets) start lower. Wildcard CORS, auth removals, and deleted assertions drop trust fast.

## State paths

```
plugins/change-tracker/state/changes.jsonl      (append-only)
plugins/trust-scorer/state/trust.json           (mutable, per-file Beta)
plugins/trust-scorer/state/learnings.json       (mutable, V6 EMA priors)
plugins/decision-gate/state/metrics.jsonl       (append-only, advisories)
plugins/session-memory/state/session-graph.json (mutable, continuity)
plugins/session-memory/state/session-summary.md (mutable, human-readable)
```

Never write these directly — owned by hooks and agents.

## Agent tiers

All 4 agents documented in `./plugins/*/agents/*.md` with explicit output contracts. Tiers follow the @enchanted-plugins convention (Orchestrator/Opus, Executor/Sonnet, Validator/Haiku):

- `classifier` (Haiku) · `auditor` (Haiku) · `restorer` (Haiku) — validators
- `adversary` (Sonnet) — executor (diff-grounded reasoning needs real analysis)

## Anti-patterns

- **Queue reordering.** Presenting the review queue in your own ordering (most recent, smallest, etc). IG ordering is the product; overriding it defeats the point.
- **Test-assertion deletion.** Removing `expect`/`assert` calls to make tests pass. V1 classifies this as `test_change` with punitive likelihood; trust collapses below 0.2 fast.
- **Silent override.** Waiving a low-trust flag without surfacing it. V6 adapts priors from real decisions; unlogged overrides poison learning.
- **Re-read `changes.jsonl` every turn.** It's append-only; read once per session or when explicitly asked for fresh state. Repeated reads waste context (and trigger Allay's A5 duplicate block if co-installed).
- **State-file mutation.** Editing `trust.json`, `changes.jsonl`, or `session-graph.json` by hand to silence a flag. Breaks V2's posterior and V6's EMA.
