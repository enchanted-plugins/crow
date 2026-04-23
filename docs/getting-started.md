# Getting started with Crow

Crow watches every edit Claude makes and scores it. Semantic diff first, then Bayesian trust. The goal: catch untrustworthy changes before they reach your branch. This page gets you from zero to a live trust readout in under 5 minutes.

## 1. Install (60 seconds)

```
/plugin marketplace add enchanted-plugins/raven
/plugin install full@raven
/plugin list
```

You should see four Crow sub-plugins including `change-tracker`, `trust-scorer`, `decision-gate`, and `session-memory`. If any are missing, see [installation.md](installation.md).

## 2. Make a change and watch

Start a normal Claude Code session. Ask Claude to edit any file. When the Write/Edit tool returns, Crow's `change-tracker` post-tool hook fires automatically and computes:

- **Semantic diff (H1)** — what the change *means*, not just what the bytes are.
- **Info-gain (H3)** — how surprising this change is relative to recent edits.

## 3. Inspect the trust score

```
/trust
```

Shows the Bayesian trust score (H2) per recent change:

```
path/to/file.py    0.92  HIGH    — small scope, matches prior pattern
other/file.md      0.41  LOW     — large rewrite, low continuity, review manually
```

Trust updates live as more evidence accumulates — a change that looked risky in isolation may score higher after subsequent edits confirm intent.

## 4. Review the running change set

```
/changes
```

Lists every edit in the current session with its trust band, grouped by file. Use this before you commit: low-trust rows are candidates for a second pair of eyes.

## 5. Gate a risky action

For destructive or cross-cutting operations, the `decision-gate` plugin inserts a review step:

```
/review
```

Surfaces the staged changes plus Crow's trust summary in one view. You can approve, ask Claude to patch specific rows, or roll back the session to the last high-trust checkpoint.

## 6. Continuity across compaction

```
/session
```

Session-memory (H4) persists the continuity graph across compaction. When the window resets, your trust history survives.

## Next steps

- [examples/README.md](../examples/README.md) — real diffs + the trust scores Crow assigned them.
- [THREAT_MODEL.md](../THREAT_MODEL.md) — attacker inputs and trust-gaming surfaces Crow is hardened against.
- [docs/science/README.md](science/README.md) — Bayesian trust, semantic diff, info-gain, continuity, adversarial robustness, session learning — derived.
- [docs/architecture/](architecture/) — auto-generated diagram.

Broken first run? → [troubleshooting.md](troubleshooting.md).
