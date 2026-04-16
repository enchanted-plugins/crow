# Hornet — What You Need To Know

You have Hornet installed. It tracks every file you change, scores each change for trust via a Bayesian model, orders what to review by information gain, and preserves the decision graph across compaction.

## What's happening behind the scenes

Every time you use Write, Edit, or MultiEdit:
1. **change-tracker** (PostToolUse) classifies the change (source / config / test / docs / schema / dependency), clusters related edits, writes `changes.jsonl` (V1 — Semantic Diff Compression)
2. **trust-scorer** (PostToolUse) updates a Beta-Bernoulli posterior per file and writes `trust.json` (V2 — Bayesian Trust Scoring)
3. **decision-gate** (PreToolUse) ranks pending reviews by information gain and may emit an advisory to stderr; for trust < 0.4 it generates targeted adversarial questions (V3 — Information-Gain Ordering, V5 — Adversarial Self-Review)

Before compaction:
4. **session-memory** (PreCompact) builds a continuity graph (files, decisions, edges) and writes `session-graph.json` + `session-summary.md` (V4 — Continuity Graph)

Across sessions:
5. **Gauss Learning** (V6) updates per-type trust priors via EMA (α=0.3) in `learnings.json` — over time Hornet adapts to this developer's patterns.

## Trust scores — what they mean

| Score | Meaning | Your action |
|-------|---------|-------------|
| 0.8+ | High trust — safe pattern | No review needed |
| 0.4–0.8 | Moderate — uncertain | Optional review; mention to developer |
| 0.2–0.4 | Low — suspicious pattern | Pause. Explain what you changed and why |
| < 0.2 | Critical — likely wrong | Stop writing this file. Surface to developer before proceeding |

Priors: all files start at Beta(2, 2) (mean 0.5). Docs/tests push trust up; config/schema push it down. Reverts halve the likelihood. Sensitive files (.env, credentials, secrets) start lower. Wildcard CORS, auth removals, and deleted test assertions drop trust fast.

## Information gain — what gets reviewed first

Decision-gate ranks by `IG(trust) = -p log p - (1-p) log(1-p)`. Maximum at trust 0.5 — uncertain changes get reviewed first. Trust near 0.1 or 0.9 is already decided; low IG. When surfacing a review queue, respect this ordering: don't lead with a 0.95-trust doc change.

## What you MUST do

1. **When you see `[Hornet]` in stderr**: Acknowledge it to the developer. Name what Hornet flagged, the trust score, and why.

2. **When trust drops below 0.4**: Pause. Explain what you changed and why. Don't keep writing to that file without addressing the concern. If decision-gate emitted adversarial questions, answer them specifically — they're generated from the actual diff, not a boilerplate.

3. **When trust drops below 0.2**: Stop writing to that file. Tell the developer: "Hornet flagged this as critical. Here's what I changed and what could go wrong." Do not continue until acknowledged.

4. **When the developer asks "what changed" or "is this safe"**: Read `plugins/change-tracker/state/changes.jsonl` and `plugins/trust-scorer/state/trust.json`. Give a semantic summary grouped by change type — not a raw file list. Lead with the riskiest files first (lowest trust).

5. **When the developer asks what to review**: Read `plugins/decision-gate/state/metrics.jsonl` and surface the IG-ranked queue. Don't just dump every file — the whole point is to reduce review load.

6. **After compaction**: Read `plugins/session-memory/state/session-summary.md` and `plugins/session-memory/state/session-graph.json`. Brief the developer: "Last session: N changes, M low-trust flagged, K advisories issued." Then resume.

7. **When the developer overrides a trust flag**: Note it. V6 Gauss Learning will adapt the prior for similar future changes — but only if the override is honest. Don't silently dismiss flags "to keep moving."

## Commands the developer can use

- `/hornet:changes` — files touched, grouped by type and cluster
- `/hornet:trust` — trust scores sorted riskiest-first
- `/hornet:review` — IG-ranked review queue with adversarial questions for low-trust changes
- `/hornet:session` — full session dashboard (continuity graph + learnings)

## State layout

```
plugins/change-tracker/state/changes.jsonl     # every change, classified + clustered
plugins/trust-scorer/state/trust.json          # per-file Beta(α,β) + trust
plugins/trust-scorer/state/learnings.json      # cross-session EMA priors (V6)
plugins/decision-gate/state/metrics.jsonl      # review advisories issued
plugins/session-memory/state/session-graph.json   # continuity graph
plugins/session-memory/state/session-summary.md   # human-readable recap
```

## Agent tiers

| Agent | Model | Plugin | Role |
|-------|-------|--------|------|
| classifier | Haiku | change-tracker | Deep semantic classification when heuristics are ambiguous |
| auditor | Haiku | trust-scorer | Trust distribution analysis + risk report |
| adversary | Sonnet | decision-gate | Targeted adversarial questions for low-trust diffs |
| restorer | Haiku | session-memory | Autonomous context restoration post-compaction |

Respect the tiering. The adversary is Sonnet because specific diff-grounded questions need real reasoning; classification and validation stay on Haiku.

## What NOT to do

- Don't suppress or dismiss Hornet warnings — the advisories exist because the diff looked wrong
- Don't modify Hornet state files directly (`trust.json`, `changes.jsonl`, `session-graph.json`)
- Don't delete test assertions to make tests pass — trust-scorer catches it and the change drops below 0.2
- Don't add wildcard CORS, disable auth, or remove rate limiters without explaining why — these are low-likelihood changes by design
- Don't reorder or summarize the review queue by your own criteria — IG ordering is the product
- Don't re-read `changes.jsonl` on every turn — the file is append-only; read once per session unless explicitly asked for fresh state
