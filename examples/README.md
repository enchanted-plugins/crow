# Examples

Real diffs Crow scored, with the trust scores it assigned and why. Use these as calibration: if you disagree with a score, that's useful feedback — file a Discussion or an issue so the rubric can evolve.

This directory is for **reference**, not for execution. Each subdirectory is self-contained: a diff, a one-page write-up, and the score Crow produced when the example was captured.

## How to read an example

Each example folder contains:

```
examples/<slug>/
├── diff.patch          Unified diff as Crow received it
├── context.md          Session context — what was being asked, what turn this was
├── score.json          Crow's output: overall band + per-engine scores
└── notes.md            Commentary — why Crow scored it that way, what to notice
```

## Trust bands

Every example lands in one of three bands:

| Band | Score range | Meaning |
|------|-------------|---------|
| HIGH | ≥ 0.80 | Small scope, matches prior pattern, high continuity, low info-gain — routine. |
| MEDIUM | 0.50 – 0.79 | Worth a second look; nothing alarming but not boilerplate either. |
| LOW | < 0.50 | Large rewrite, low continuity, high info-gain, or adversarial signals — review manually. |

Bands are advisory. A LOW row can be correct; a HIGH row can be malicious. The band tells you **how much attention to spend**, not what the answer is.

## Suggested first read

If you're new to Crow's scoring, read these three examples in order. Each demonstrates a different engine.

1. `simple-rename/` — HIGH. Demonstrates H1 Semantic Diff recognizing a non-semantic change.
2. `config-flip/` — LOW. Demonstrates H3 Info-Gain catching a small-textual / large-semantic change.
3. `gradual-drift/` — medium-then-LOW sequence. Demonstrates H4 Continuity resisting a warmup + payload attack.

## Contributing examples

Have a real edit that Crow scored interestingly? Submit a PR that adds:

- A new subdirectory under `examples/<slug>/`.
- The four files above.
- A pointer entry below.

**Rules for examples:**

- Real diffs only. No hand-crafted gotchas — calibration is only useful against the distribution we actually see.
- Anonymize paths if the original repo is private. Function names and intent stay; proprietary identifiers go.
- If you disagree with Crow's score, say so in `notes.md`. Disagreement is the input that improves the rubric.

## Index

<!--
Populate this list as examples land. Keep one line per example for easy scan.
Format: | <slug> | <band> | <one-line what-it-demonstrates> |
-->

| Slug | Band | Demonstrates |
|------|------|--------------|
| _TBD_ | | |

## Related

- [docs/science/README.md](../docs/science/README.md) — the engines (H1–H6) referenced here.
- [docs/glossary.md](../docs/glossary.md) *(if present)* — definitions of terms used in the write-ups.
- [THREAT_MODEL.md](../THREAT_MODEL.md) — the adversarial surfaces Crow is hardened against; some examples are drawn from this list.
