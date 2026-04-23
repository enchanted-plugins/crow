# Frequently asked questions

Quick answers to questions that don't yet have their own doc. For anything deeper, follow the links — the full answer usually lives in a neighboring file.

## What's the difference between Crow and the other siblings?

Crow answers *"what just happened?"* — it watches every edit and scores trust before it influences a commit. Sibling plugins answer different questions in the same session: Wixie engineers prompts, Fae tracks token spend, Hydra scans for security surface, Sylph coordinates git workflow. All are independent installs; none require the others. See [docs/ecosystem.md](ecosystem.md) for the full map.

## Do I need the other siblings to use Crow?

No. Crow is self-contained — install `full@raven` and every command works standalone. Sylph cross-references Crow's trust scores if both are installed, but Crow does not require Sylph and vice versa.

## How do I report a bug vs. ask a question vs. disclose a security issue?

- **Security vulnerability** — private advisory, never a public issue. See [SECURITY.md](../SECURITY.md).
- **Reproducible bug** — a bug report issue with repro steps + exact versions.
- **Usage question or half-formed idea** — [Discussions](https://github.com/enchanted-plugins/raven/discussions).

The [SUPPORT.md](../SUPPORT.md) page has the exact links for each.

## Is Crow an official Anthropic product?

No. Crow is an independent open-source plugin for [Claude Code](https://github.com/anthropics/claude-code) (Anthropic's CLI). It's published by [enchanted-plugins](https://github.com/enchanted-plugins) under the MIT license and is not affiliated with, endorsed by, or supported by Anthropic.

## How does Crow resist trust-inflation attacks?

Every identified gaming surface — look-alike edits, gradual-drift warmups, token-splitting / encoding bypass, prompt injection via fetched content, history manipulation, reviewer-fatigue attacks — has a specific counter documented in [THREAT_MODEL.md](../THREAT_MODEL.md). The scoring path is deterministic arithmetic over the diff plus session history; it does not consult an LLM to decide trust, so content injected into a diff is treated as data, not instruction.

## What's the difference between HIGH, MEDIUM, and LOW trust?

Bands are advisory signal, not verdicts:

- **HIGH (≥ 0.80)** — small scope, matches prior pattern, high continuity, low info-gain. Routine.
- **MEDIUM (0.50–0.79)** — worth a second look; nothing alarming but not boilerplate either.
- **LOW (< 0.50)** — large rewrite, low continuity, high info-gain, or adversarial signals. Review manually.

A LOW row can be correct; a HIGH row can be malicious. The band tells you *how much attention to spend*, not what the answer is. Full rubric in [docs/glossary.md](glossary.md).
