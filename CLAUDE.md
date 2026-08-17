# Crow — Agent Contract

Audience: Claude. Crow watches file changes, runs a stateless content-detector suite that flags risky changes with a severity, orders reviews by that severity, and preserves the decision graph across compaction.

## Shared behavioral modules

These apply to every skill in every plugin. Load once; do not re-derive.

- @../vis/packages/core/conduct/discipline.md — coding conduct: think-first, simplicity, surgical edits, goal-driven loops
- @../vis/packages/core/conduct/capability-fidelity.md — contracts survive capability gaps: recover, escalate, or abort; never silently substitute
- @../vis/packages/core/conduct/context.md — attention-budget hygiene, U-curve placement, checkpoint protocol
- @../vis/packages/core/conduct/verification.md — independent checks, baseline snapshots, dry-run for destructive ops
- @../vis/packages/core/conduct/verdict-calibration.md — every verdict (DEPLOY/PASS/COMPLETE/VERIFIED) carries n, sampling method, and a calibration qualifier; vis-side abstraction over the wixie DEPLOY bar
- @../vis/packages/core/conduct/doubt-engine.md — adversarial self-check before agreement; counter to F01 sycophancy; fires on user proposals AND your own prior framing
- @../vis/packages/core/conduct/delegation.md — subagent contracts, tool whitelisting, parallel vs. serial rules
- @../vis/packages/core/conduct/failure-modes.md — 14-code taxonomy for accumulated-learning logs
- @../vis/packages/core/conduct/tool-use.md — tool-choice hygiene, error payload contract, parallel-dispatch rules
- @../vis/packages/skills/conduct/skill-authoring.md — SKILL.md frontmatter discipline, discovery test
- @../vis/packages/core/conduct/hooks.md — advisory-only hooks, injection over denial, fail-open
- @../vis/packages/core/conduct/metacognition.md — periodic goal-restate; fires every K=8 tool-uses or on user meta-question
- @../vis/packages/core/conduct/precedent.md — log self-observed failures to `state/precedent-log.md`; consult before risky steps
- @../vis/packages/core/conduct/precedent-freshness.md — verify self-authored memory/precedent/briefings before relying on them: Class-A surfaces (path/function/flag) get a Glob/Grep existence check; Class-B snapshots get a git-log freshness check; Class-C feedback rules are trusted unless contradicted
- @../vis/packages/core/conduct/prior-art-discovery.md — F28 counter: run the 5-target discovery pass (shared/scripts, packages/*/skills, state/proposals, slug-glob, signature-grep) before authoring a new tool/script/skill/module
- @../vis/packages/core/conduct/reversibility-foresight.md — classify action reversibility (trivial/costly/impossible) before acting; confirmation scales with tier
- @../vis/packages/core/conduct/substrate-consumption.md — read-side complement to precedent.md: consume briefing, MEMORY, learnings, and precedent before acting; counter to F24 substrate-blindness
- @../vis/packages/core/conduct/sunk-cost-iteration.md — stop-and-re-ask after 2 INCONCLUSIVE/BLOCKED results on the same artifact; iteration is not an authorization to keep patching
- @../vis/packages/core/conduct/tier-sizing.md — prompt verbosity scales inversely with model tier; Haiku needs mechanical steps, Opus runs on intent
- @../vis/packages/web/conduct/web-fetch.md — external URL handling: cache, dedup, budget; WebFetch is Haiku-tier-only

When a module conflicts with a plugin-local instruction, the plugin wins — but log the override.

## Lifecycle

| Plugin | Hook | Purpose |
|--------|------|---------|
| decision-gate | PostToolUse (Write\|Edit\|MultiEdit) | Advisory gate; adversarial questions for flagged changes (V3, V5) |
| change-tracker | PostToolUse (Write\|Edit\|MultiEdit) | Semantic diff compression + classification (V1) |
| trust-scorer | PostToolUse (Write\|Edit\|MultiEdit) | Stateless content-detector suite → flags + severity (V2) |
| session-memory | PreCompact | Continuity graph + Exponential Strategy Averaging (V4, V6) |

## Algorithms

V1 Semantic Diff Compression · V2 Content-Detector Suite · V3 Severity-Ordered Review · V4 Session Continuity Graph · V5 Adversarial Self-Review · V6 Exponential Strategy Averaging. Derivations in `README.md` § *The Science Behind Crow*.

## Behavioral contracts

Markers: **[H]** hook-enforced · **[A]** advisory.

1. **[H] IMPORTANT — Acknowledge the `[Crow]` stderr.** Name what was flagged, its severity, the flags that fired, and the change type. Silence after an advisory is a contract violation. There is no numeric trust score — never invent one.
2. **[A] YOU MUST pause at WARNING/HIGH.** Explain what you changed and why. Do not continue writing the same file without addressing the flag. If decision-gate (V5) emitted adversarial questions, answer them specifically — they're generated from the diff, not boilerplate.
3. **[A] YOU MUST stop at CRITICAL.** Surface to the developer: "Crow flagged this as critical (`<flag>`). Here's what I changed and what could go wrong." Do not resume until acknowledged.
4. **[A] Respect severity ordering.** When surfacing a review queue, lead with the most severe (CRITICAL → HIGH → WARNING), not the newest. There is no information-gain / entropy ordering — that required a trust probability Crow no longer computes.
5. **[A] ESCALATE on override.** If the developer waives a flag, note it honestly. V6 Exponential Strategy Averaging tracks per-type flag rates across sessions from real overrides; silent dismissals poison the EMA.
6. **[A] Restore before resume.** After compaction, read `plugins/session-memory/state/session-summary.md` and brief: "Last session: N changes, M flagged, K advisories." Then resume.

## Severity bands (V2)

Severity is the max over the content-detector flags that fired. No score.

| Severity | Flags | Action |
|----------|-------|--------|
| CRITICAL | `exposed_secrets`, `gutted_test` | Stop; surface to developer |
| HIGH | `weak_crypto`, `wildcard_cors` | Pause; explain change; answer adversarial questions |
| WARNING | `trivial_assertions`, `very_short_file`, `debug_enabled`, `reverted` | Mention to developer; quick look |
| clean | no flag fired | No review needed (absence of a match, not proof of correctness) |

Each change is assessed statelessly from its own content — no priors, no accumulation. Wildcard CORS, weak crypto, exposed secrets, and deleted assertions flag immediately.

## State paths

```
plugins/change-tracker/state/changes.jsonl      (append-only)
plugins/trust-scorer/state/metrics.jsonl        (append-only, change_flagged events)
plugins/trust-scorer/state/learnings.json       (mutable, V6 EMA flag-rate priors)
plugins/decision-gate/state/metrics.jsonl       (append-only, advisories)
plugins/session-memory/state/session-graph.json (mutable, continuity)
plugins/session-memory/state/session-summary.md (mutable, human-readable)
```

Never write these directly — owned by hooks and agents.

## Agent tiers

All 4 agents documented in `./plugins/*/agents/*.md` with explicit output contracts. Tiers follow the @enchanter-ai convention (Orchestrator/Opus, Executor/Sonnet, Validator/Haiku):

- `classifier` (Haiku) · `auditor` (Haiku) · `restorer` (Haiku) — validators
- `adversary` (Sonnet) — executor (diff-grounded reasoning needs real analysis)

## Anti-patterns

- **Queue reordering.** Presenting the review queue in your own ordering (most recent, smallest, etc). Severity ordering is the product; overriding it defeats the point.
- **Test-assertion deletion.** Removing `expect`/`assert` calls to make tests pass. The detector flags this as `gutted_test` (CRITICAL) when all assertions become trivial.
- **Silent override.** Waiving a flag without surfacing it. V6 adapts flag-rate priors from real decisions; unlogged overrides poison learning.
- **Re-read `changes.jsonl` every turn.** It's append-only; read once per session or when explicitly asked for fresh state. Repeated reads waste context (and trigger Emu's A5 duplicate block if co-installed).
- **Inventing a trust score.** Crow emits flags + a severity, never a number. Never report a "trust score", probability, or Beta parameter — they do not exist.
- **State-file mutation.** Editing `metrics.jsonl`, `changes.jsonl`, or `session-graph.json` by hand to silence a flag. Breaks V2's detectors and V6's EMA.
