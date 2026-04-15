# Claude Code Configuration

This directory contains example Claude Code configuration snippets for use with Vigil.

## Installing Plugins

After cloning the Vigil repo, add plugins to Claude Code:

```bash
# Add the marketplace (recommended)
/plugin marketplace add /path/to/vigil

# Or add individual plugins
/plugin add /path/to/vigil/plugins/change-tracker
/plugin add /path/to/vigil/plugins/trust-scorer
/plugin add /path/to/vigil/plugins/decision-gate
/plugin add /path/to/vigil/plugins/session-memory
```

## Recommended Install Order

1. **change-tracker** — Install first. Foundation for all other plugins. Tracks changes and classifies them.
2. **trust-scorer** — Install second. Reads change data and computes Bayesian trust scores.
3. **decision-gate** — Install third. Reads trust scores and surfaces review advisories.
4. **session-memory** — Install fourth. Aggregates data from all plugins for compaction survival.

## Plugin Dependencies

```
change-tracker → trust-scorer → decision-gate
                                      ↓
                  session-memory ← reads all three
```

Each plugin degrades gracefully if siblings are missing. change-tracker works standalone.
trust-scorer works without decision-gate. session-memory works with whatever data is available.
