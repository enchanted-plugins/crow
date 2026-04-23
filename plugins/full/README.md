# full

**Meta-plugin. Installs every Crow plugin at once.**

This plugin has no hooks, skills, or agents of its own. It exists so you can install the whole 4-plugin pipeline with one command:

```
/plugin marketplace add enchanted-plugins/crow
/plugin install full@crow
```

Claude Code resolves the four dependencies and installs:

- `crow-change-tracker` — semantic diff compression + classification
- `crow-decision-gate` — information-gain review + adversarial questions
- `crow-session-memory` — continuity graph, compaction survival
- `crow-trust-scorer` — Bayesian posterior per file change

If you want to cherry-pick a single plugin (e.g. just `crow-trust-scorer`), you can — but the plugins feed each other at runtime (change-tracker → trust-scorer → decision-gate → session-memory), so you'll typically want them all.

## Behavioral modules

Inherits the [shared behavioral modules](../../shared/) via root [CLAUDE.md](../../CLAUDE.md) — discipline, context, verification, delegation, failure-modes, tool-use, skill-authoring, hooks, precedent.
