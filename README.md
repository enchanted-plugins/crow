# Hornet

<p>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-3fb950?style=for-the-badge"></a>
  <img alt="4 plugins" src="https://img.shields.io/badge/Plugins-4-bc8cff?style=for-the-badge">
  <img alt="6 algorithms" src="https://img.shields.io/badge/Algorithms-6-58a6ff?style=for-the-badge">
  <img alt="4 agents" src="https://img.shields.io/badge/Agents-4-d29922?style=for-the-badge">
  <img alt="Bayesian trust scoring" src="https://img.shields.io/badge/Bayesian-Trust-f0883e?style=for-the-badge">
</p>

> An @enchanted-plugins product — algorithm-driven, agent-managed, self-learning.

Real-time change comprehension. Bayesian trust scoring. Information-gain review.

**4 plugins. 6 algorithms. 4 agents. Every change accounted for.**

> Claude changed 12 files in 8 turns. I didn't read a single diff. Hornet told me
> the auth migration was safe (trust: 0.82), the config change was not (trust: 0.31),
> and the test deletions were adversarial (trust: 0.18). I reviewed 2 files instead of 12.

## Origin

Hornet takes her name from **Hornet of Hollow Knight** — an explorer who survives hostile terrain by observing carefully before every move. Every AI-assisted edit is hostile terrain until its diff has been read; Hornet reads it for you and scores trust before it reaches main.

The question this plugin answers: *What just happened?*

## Contents

- [The Problem](#the-problem)
- [How It Works](#how-it-works)
- [The Full Lifecycle](#the-full-lifecycle)
- [Install](#install)
- [4 Plugins, 4 Agents, 6 Algorithms](#4-plugins-4-agents-6-algorithms)
- [What You Get Per Session](#what-you-get-per-session)
- [The Science Behind Hornet](#the-science-behind-hornet)
- [Commands](#commands)
- [How Trust Scoring Works](#how-trust-scoring-works)
- [How Information-Gain Ordering Works](#how-information-gain-ordering-works)
- [vs Everything Else](#vs-everything-else)
- [Agent Conduct (9 Modules)](#agent-conduct-9-modules)
- [Architecture](#architecture)
- [Contributing](#contributing)
- [License](#license)

## The Problem

The review-and-comprehension loop eats 40-60% of every Claude Code session:
- Developers rubber-stamp 93% of permission prompts (Anthropic data)
- Developers start second Claude instances to review the first (Issue #1144)
- The diff UI shows +7,490/-6,880 for an 11-line change (Issue #18541)
- No per-hunk accept/discard exists (Issue #31395)
- 10-20% of sessions are abandoned due to unexpected changes

## How It Works

Four plugins, one concern each, bound to specific hook points. **decision-gate** on `PreToolUse` orders pending reviews by information gain (H3) and red-teams low-trust changes (H5). **change-tracker** on `PostToolUse` classifies and clusters every diff (H1). **trust-scorer** on `PostToolUse` updates a Beta-Bernoulli posterior per file (H2). **session-memory** on `PreCompact` builds a continuity graph and persists cross-session learnings (H4, H6). The diagram below shows the bindings and state outputs.

<p align="center">
  <a href="docs/assets/pipeline.mmd" title="View hook-binding diagram source (Mermaid)">
    <img src="docs/assets/pipeline.svg"
         alt="Hornet hook bindings: Claude Code file changes fan out into decision-gate (PreToolUse · H3/H5), change-tracker (PostToolUse · H1), trust-scorer (PostToolUse · H2), session-memory (PreCompact · H4/H6); each plugin emits its own state artifact (advisory, changes.jsonl, trust.json, session-graph.json)"
         width="100%" style="max-width:1100px;">
  </a>
</p>

<sub align="center">

Source: [docs/assets/pipeline.mmd](docs/assets/pipeline.mmd) · Regeneration command in [docs/assets/README.md](docs/assets/README.md).

</sub>

Each plugin owns one concern. No overlap. No dependencies between plugins.

## The Full Lifecycle

Every file change passes the `PreToolUse` gate (decision-gate), the tool executes, then `PostToolUse` updates change-tracker and trust-scorer. When context fills, `PreCompact` triggers session-memory to write `session-graph.json` before the wipe. On resume, the restorer agent reads it back autonomously.

<p align="center">
  <a href="docs/assets/lifecycle.mmd" title="View session-lifecycle diagram source (Mermaid)">
    <img src="docs/assets/lifecycle.svg"
         alt="Hornet session lifecycle: session start, file change, PreToolUse (decision-gate) runs trust-check and IG ranking, tool executes, PostToolUse (change-tracker + trust-scorer) classifies and updates posterior; compaction triggers PreCompact (session-memory) to write session-graph.json; context wiped; restorer agent rebuilds; session continues"
         width="100%" style="max-width:1100px;">
  </a>
</p>

<sub align="center">

Source: [docs/assets/lifecycle.mmd](docs/assets/lifecycle.mmd) · Regeneration command in [docs/assets/README.md](docs/assets/README.md).

</sub>

## Install

Hornet ships as 4 plugins that feed each other (change-tracker → trust-scorer → decision-gate → session-memory). One meta-plugin — `full` — lists all four as dependencies, so a single install pulls in the whole chain.

**In Claude Code** (recommended):

```
/plugin marketplace add enchanted-plugins/hornet
/plugin install full@hornet
```

Claude Code resolves the dependency list and installs all 4 plugins. Verify with `/plugin list`.

**Want to cherry-pick?** Individual plugins are still installable by name — e.g. `/plugin install hornet-trust-scorer@hornet` if you only need scoring. The pipeline is designed to work end-to-end, though, so `full@hornet` is the path we recommend.

**Via shell** (also installs `shared/*.sh` and `shared/scripts/*.py` locally so hooks work offline):

```bash
bash <(curl -s https://raw.githubusercontent.com/enchanted-plugins/hornet/main/install.sh)
```

## 4 Plugins, 4 Agents, 6 Algorithms

| Plugin | Hook | Command | What |
|--------|------|---------|------|
| change-tracker | PostToolUse | `/hornet:changes` | Semantic diff compression + classification |
| trust-scorer | PostToolUse | `/hornet:trust` | Bayesian trust scoring + alerts |
| decision-gate | PreToolUse | `/hornet:review` | IG-ordered review + adversarial questions |
| session-memory | PreCompact | `/hornet:session` | Continuity graph + Gauss learning |

| Agent | Model | Plugin | What |
|-------|-------|--------|------|
| classifier | Haiku | change-tracker | Deep semantic change classification |
| auditor | Haiku | trust-scorer | Trust distribution analysis + risk report |
| adversary | Sonnet | decision-gate | Targeted adversarial review questions |
| restorer | Haiku | session-memory | Autonomous context restoration |

## What You Get Per Session

```
change-tracker/state/
├── changes.jsonl        # Every file change with type, hash, cluster
└── metrics.jsonl        # change_tracked events

trust-scorer/state/
├── trust.json           # Per-file Beta parameters and trust scores
├── learnings.json       # Cross-session Gauss learning data
└── metrics.jsonl        # trust_scored events

decision-gate/state/
└── metrics.jsonl        # review_advisory events

session-memory/state/
├── session-graph.json   # Continuity graph (nodes, edges, trust overview)
├── session-summary.md   # Human-readable session recap
└── metrics.jsonl        # session_saved events
```

## The Science Behind Hornet

Six named algorithms power every decision:

### H1. Semantic Diff Compression (Change Tracker)

Raw diffs are noise. Hornet classifies each change by type and clusters related changes across files.

Change types: `source_code`, `config_change`, `test_change`, `documentation`, `schema_change`, `dependency_change`.
Impact radius: local (1 file), module (2-5 files), systemic (6+ files).

<p align="center"><img src="docs/assets/math/h1-classify.svg" alt="classify(f) = config if .json/.yaml/.env; test if test/spec; schema if .sql/migration; source otherwise"></p>

### H2. Bayesian Trust Scoring (Trust Scorer)

Each file change gets a trust score using Beta-Bernoulli conjugate priors.

<p align="center"><img src="docs/assets/math/h2-bayes.svg" alt="P(theta | D) = P(D | theta) · P(theta) / P(D); P(theta) = Beta(alpha, beta)"></p>

<p align="center"><img src="docs/assets/math/h2-update.svg" alt="alpha_new = alpha + l; beta_new = beta + (1 - l); trust = alpha / (alpha + beta)"></p>

Prior: Beta(2, 2) — mildly uncertain. Update via change-type likelihood ℓ. Trust reported as the posterior mean.

| Change Type | Likelihood ℓ |
|-------------|------------------|
| Documentation | 0.95 |
| Test changes | 0.85 |
| Source code (small) | 0.70 |
| Source code (large) | 0.50 |
| Schema changes | 0.55 |
| Dependencies | 0.50 |
| Config (sensitive) | 0.30 |

### H3. Information-Gain Decision Support (Decision Gate)

Help the developer review efficiently by showing the most uncertain changes first.

<p align="center"><img src="docs/assets/math/h3-infogain.svg" alt="IG(X) = H(X) = -p log2(p) - (1-p) log2(1-p)"></p>

Maximum at p = 0.5 (trust is most uncertain). Changes at trust 0.5 get reviewed first. Changes at trust 0.1 or 0.9 are already decided — low review value.

### H4. Session Continuity Graph (Session Memory)

Before compaction, build a semantic graph:
- Nodes: files (with type, trust, change count), decisions (review advisories)
- Edges: cluster relationships, file-to-decision links

On resumption: "Last session: 15 changes, 2 low-trust files flagged, 3 advisories issued."

### H5. Adversarial Self-Review (Decision Gate extension)

For low-trust changes (trust < 0.4), generate specific adversarial questions:
- "This changes the database query from parameterized to string interpolation. SQL injection risk."
- "This test now asserts `true === true`. The original checked actual business logic."
- "This deletes the rate limiter. Was rate limiting intentional?"

Not generic warnings. Specific to the diff content.

### H6. Gauss Learning (Cross-Session)

Exponential moving average over per-type trust rates across sessions.

<p align="center"><img src="docs/assets/math/h6-gauss.svg" alt="r_new = alpha · s_current + (1 - alpha) · r_prior; alpha = 0.3"></p>

After N sessions, Hornet knows: config changes always get flagged, test changes are usually safe,
this developer always reviews schema changes carefully. Adapts priors accordingly.

## Commands

| Command | Plugin | What |
|---------|--------|------|
| `/hornet:changes` | change-tracker | All changes grouped by type and file |
| `/hornet:trust` | trust-scorer | Trust scores sorted riskiest-first |
| `/hornet:review` | decision-gate | IG-ranked review queue with adversarial questions |
| `/hornet:session` | session-memory | Full session dashboard |

## How Trust Scoring Works

1. Every file starts at Beta(2, 2) — a mildly uncertain prior (mean = 0.5).
2. Each Write/Edit updates the posterior: high-trust types (docs, tests) push the score up, risky types (config, schema) push it down.
3. After multiple updates, the posterior narrows — confidence increases.
4. Reverts are penalized: if a file returns to a previous hash, the likelihood is halved.
5. Trust scores persist across the session via `trust.json`. Cross-session learning via `learnings.json`.

## How Information-Gain Ordering Works

Not all files are equally worth reviewing. Hornet ranks by uncertainty:
- Trust 0.5 → IG 1.0 (maximum uncertainty — you need to look at this)
- Trust 0.1 → IG 0.47 (clearly bad — you already know)
- Trust 0.9 → IG 0.47 (clearly good — don't waste time)

Review the uncertain files first. Skip the ones where trust is already decided.

## vs Everything Else

| | Hornet | Gryph | Context Mode | ClaudeWatch | Anthropic Review |
|---|---|---|---|---|---|
| Real-time awareness | in-session | post-hoc | — | — | post-PR |
| Trust scoring | Bayesian | — | — | — | — |
| Per-change review | IG-ordered | — | — | — | — |
| Adversarial questions | specific | — | — | — | generic |
| Session continuity | graph + learnings | — | — | — | — |
| Cross-session learning | Gauss EMA | — | — | — | — |
| Dependencies | bash + jq | Node | Node + MCP | Python | API |

## Agent Conduct (9 Modules)

Every skill inherits a reusable behavioral contract from [shared/](shared/) — loaded once into [CLAUDE.md](CLAUDE.md), applied across all plugins. This is how Claude *acts* inside Hornet: deterministic, surgical, verifiable. Not a suggestion; a contract.

| Module | What it governs |
|--------|-----------------|
| [discipline.md](shared/conduct/discipline.md) | Coding conduct: think-first, simplicity, surgical edits, goal-driven loops |
| [context.md](shared/conduct/context.md) | Attention-budget hygiene, U-curve placement, checkpoint protocol |
| [verification.md](shared/conduct/verification.md) | Independent checks, baseline snapshots, dry-run for destructive ops |
| [delegation.md](shared/conduct/delegation.md) | Subagent contracts, tool whitelisting, parallel vs. serial rules |
| [failure-modes.md](shared/conduct/failure-modes.md) | 14-code taxonomy for accumulated-learning logs |
| [tool-use.md](shared/conduct/tool-use.md) | Tool-choice hygiene, error payload contract, parallel-dispatch rules |
| [skill-authoring.md](shared/conduct/skill-authoring.md) | SKILL.md frontmatter discipline, discovery test |
| [hooks.md](shared/conduct/hooks.md) | Advisory-only hooks, injection over denial, fail-open |
| [precedent.md](shared/conduct/precedent.md) | Log self-observed failures to `state/precedent-log.md`; consult before risky steps |

## Architecture

Interactive architecture explorer with plugin diagrams, agent cards, and data flow:

**[docs/architecture/](docs/architecture/)** — auto-generated from the codebase. Run `python docs/architecture/generate.py` to regenerate.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)

## License

MIT
