# Vigil

> An @enchanted-plugins product — algorithm-driven, agent-managed, self-learning.

Real-time change comprehension. Bayesian trust scoring. Information-gain review.

**4 plugins. 6 algorithms. 4 agents. Every change accounted for.**

> Claude changed 12 files in 8 turns. I didn't read a single diff. Vigil told me
> the auth migration was safe (trust: 0.82), the config change was not (trust: 0.31),
> and the test deletions were adversarial (trust: 0.18). I reviewed 2 files instead of 12.

## The Problem

The review-and-comprehension loop eats 40-60% of every Claude Code session:
- Developers rubber-stamp 93% of permission prompts (Anthropic data)
- Developers start second Claude instances to review the first (Issue #1144)
- The diff UI shows +7,490/-6,880 for an 11-line change (Issue #18541)
- No per-hunk accept/discard exists (Issue #31395)
- 10-20% of sessions are abandoned due to unexpected changes

## How It Works

```mermaid
graph TD
    CC(["🔧 Claude Code — File Changes"])

    CC -->|PreToolUse| DG
    CC -->|PostToolUse| CT
    CC -->|PostToolUse| TS
    CC -->|PreCompact| SM

    subgraph DG["decision-gate"]
        DG_V3["V3 Information-Gain Ordering<br/><small>prioritize what to review</small>"]
        DG_V5["V5 Adversarial Self-Review<br/><small>red-team low-trust changes</small>"]
    end

    subgraph CT["change-tracker"]
        CT_V1["V1 Semantic Diff Compression<br/><small>classify and cluster changes</small>"]
    end

    subgraph TS["trust-scorer"]
        TS_V2["V2 Bayesian Trust Model<br/><small>prior → posterior per change</small>"]
    end

    subgraph SM["session-memory"]
        SM_V4["V4 Continuity Graph<br/><small>decision history + preferences</small>"]
        SM_V6["V6 Gauss Accumulation<br/><small>cross-session learning</small>"]
    end

    DG -->|"advisory<br/>(stderr)"| OUT_DG(["gate review"])
    CT -->|"changes.jsonl"| OUT_CT(["tracked"])
    TS -->|"trust.json"| OUT_TS(["scored"])
    SM -->|"session-graph.json<br/>learnings.json"| OUT_SM(["preserved"])

    style CC fill:#0d1117,stroke:#bc8cff,color:#e6edf3
    style DG fill:#161b22,stroke:#58a6ff,color:#e6edf3
    style CT fill:#161b22,stroke:#3fb950,color:#e6edf3
    style TS fill:#161b22,stroke:#d29922,color:#e6edf3
    style SM fill:#161b22,stroke:#bc8cff,color:#e6edf3
```

Each plugin owns one concern. No overlap. No dependencies between plugins.

### Session Lifecycle

```mermaid
graph LR
    A(["Session Start"]) --> B["File Change"]
    B --> C{"PreToolUse<br/>decision-gate"}
    C -->|"trust check"| D["Tool Executes"]
    D --> E{"PostToolUse<br/>change-tracker<br/>trust-scorer"}
    E --> B
    B -.->|"Context full"| F["⚠️ Compaction"]
    F --> G{"PreCompact<br/>session-memory"}
    G -->|"session-graph.json"| H["Context Wiped"]
    H --> I["restorer agent"]
    I --> J(["Session Continues"])

    style F fill:#f85149,color:#fff
    style G fill:#d29922,color:#0d1117
    style I fill:#3fb950,color:#0d1117
```

## The Science Behind Vigil

Six named algorithms power every decision:

### V1. Semantic Diff Compression (Change Tracker)

Raw diffs are noise. Vigil classifies each change by type and clusters related changes across files.

Change types: `source_code`, `config_change`, `test_change`, `documentation`, `schema_change`, `dependency_change`.
Impact radius: local (1 file), module (2-5 files), systemic (6+ files).

$$\text{classify}(f) = \begin{cases} \text{config} & f \in \{*.json, *.yaml, *.env\} \\ \text{test} & f \in \{*test*, *spec*\} \\ \text{schema} & f \in \{*.sql, */migration/*\} \\ \text{source} & \text{otherwise} \end{cases}$$

### V2. Bayesian Trust Scoring (Trust Scorer)

Each file change gets a trust score using Beta-Bernoulli conjugate priors.

$$P(\theta | D) = \frac{P(D | \theta) \cdot P(\theta)}{P(D)}, \quad P(\theta) = \text{Beta}(\alpha, \beta)$$

Prior: $\text{Beta}(2, 2)$ — mildly uncertain.
Update: $\alpha_{new} = \alpha + \ell$, $\beta_{new} = \beta + (1 - \ell)$, where $\ell$ is the change-type likelihood.
Trust: $\frac{\alpha}{\alpha + \beta}$ (posterior mean).

| Change Type | Likelihood $\ell$ |
|-------------|------------------|
| Documentation | 0.95 |
| Test changes | 0.85 |
| Source code (small) | 0.70 |
| Source code (large) | 0.50 |
| Schema changes | 0.55 |
| Dependencies | 0.50 |
| Config (sensitive) | 0.30 |

### V3. Information-Gain Decision Support (Decision Gate)

Help the developer review efficiently by showing the most uncertain changes first.

$$IG(X) = H(X) = -p \log_2 p - (1-p) \log_2 (1-p)$$

Maximum at $p = 0.5$ (trust is most uncertain). Changes at trust 0.5 get reviewed first.
Changes at trust 0.1 or 0.9 are already decided — low review value.

### V4. Session Continuity Graph (Session Memory)

Before compaction, build a semantic graph:
- Nodes: files (with type, trust, change count), decisions (review advisories)
- Edges: cluster relationships, file-to-decision links

On resumption: "Last session: 15 changes, 2 low-trust files flagged, 3 advisories issued."

### V5. Adversarial Self-Review (Decision Gate extension)

For low-trust changes ($\text{trust} < 0.4$), generate specific adversarial questions:
- "This changes the database query from parameterized to string interpolation. SQL injection risk."
- "This test now asserts `true === true`. The original checked actual business logic."
- "This deletes the rate limiter. Was rate limiting intentional?"

Not generic warnings. Specific to the diff content.

### V6. Gauss Learning (Cross-Session)

Exponential moving average over per-type trust rates across sessions.

$$r_{new} = \alpha \cdot s_{current} + (1 - \alpha) \cdot r_{prior}, \quad \alpha = 0.3$$

After N sessions, Vigil knows: config changes always get flagged, test changes are usually safe,
this developer always reviews schema changes carefully. Adapts priors accordingly.

## Install

```
/plugin marketplace add enchanted-plugins/vigil
```

Start with change-tracker + trust-scorer:

```
/plugin install change-tracker@vigil
/plugin install trust-scorer@vigil
```

Full suite:

```
/plugin install change-tracker@vigil
/plugin install trust-scorer@vigil
/plugin install decision-gate@vigil
/plugin install session-memory@vigil
```

Or manually:

```bash
bash <(curl -s https://raw.githubusercontent.com/enchanted-plugins/vigil/main/install.sh)
```

## 4 Plugins, 4 Agents, 6 Algorithms

| Plugin | Hook | Command | What |
|--------|------|---------|------|
| change-tracker | PostToolUse | `/vigil:changes` | Semantic diff compression + classification |
| trust-scorer | PostToolUse | `/vigil:trust` | Bayesian trust scoring + alerts |
| decision-gate | PreToolUse | `/vigil:review` | IG-ordered review + adversarial questions |
| session-memory | PreCompact | `/vigil:session` | Continuity graph + Gauss learning |

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

## Commands

| Command | Plugin | What |
|---------|--------|------|
| `/vigil:changes` | change-tracker | All changes grouped by type and file |
| `/vigil:trust` | trust-scorer | Trust scores sorted riskiest-first |
| `/vigil:review` | decision-gate | IG-ranked review queue with adversarial questions |
| `/vigil:session` | session-memory | Full session dashboard |

## How Trust Scoring Works

1. Every file starts at $\text{Beta}(2, 2)$ — a mildly uncertain prior (mean = 0.5).
2. Each Write/Edit updates the posterior: high-trust types (docs, tests) push the score up, risky types (config, schema) push it down.
3. After multiple updates, the posterior narrows — confidence increases.
4. Reverts are penalized: if a file returns to a previous hash, the likelihood is halved.
5. Trust scores persist across the session via `trust.json`. Cross-session learning via `learnings.json`.

## How Information-Gain Ordering Works

Not all files are equally worth reviewing. Vigil ranks by uncertainty:
- Trust 0.5 → IG 1.0 (maximum uncertainty — you need to look at this)
- Trust 0.1 → IG 0.47 (clearly bad — you already know)
- Trust 0.9 → IG 0.47 (clearly good — don't waste time)

Review the uncertain files first. Skip the ones where trust is already decided.

## vs Everything Else

| | Vigil | Gryph | Context Mode | ClaudeWatch | Anthropic Review |
|---|---|---|---|---|---|
| Real-time awareness | in-session | post-hoc | — | — | post-PR |
| Trust scoring | Bayesian | — | — | — | — |
| Per-change review | IG-ordered | — | — | — | — |
| Adversarial questions | specific | — | — | — | generic |
| Session continuity | graph + learnings | — | — | — | — |
| Cross-session learning | Gauss EMA | — | — | — | — |
| Dependencies | bash + jq | Node | Node + MCP | Python | API |

## Architecture

Interactive architecture explorer with plugin diagrams, agent cards, and data flow:

**[docs/architecture/](docs/architecture/)** — auto-generated from the codebase. Run `python docs/architecture/generate.py` to regenerate.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)

## License

MIT
