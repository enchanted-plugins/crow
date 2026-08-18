# Frequently asked questions

Quick answers to questions that don't yet have their own doc. For anything deeper, follow the links — the full answer usually lives in a neighboring file.

## What's the difference between Crow and the other siblings?

Crow answers *"what just happened?"* — it watches every edit and scores trust before it influences a commit. Sibling plugins answer different questions in the same session: Wixie engineers prompts, Emu tracks token spend, Hydra scans for security surface, Sylph coordinates git workflow. All are independent installs; none require the others. See [docs/ecosystem.md](ecosystem.md) for the full map.

## Do I need the other siblings to use Crow?

No. Crow is self-contained — install `full@crow` and every command works standalone. Sylph cross-references Crow's change flags if both are installed, but Crow does not require Sylph and vice versa.

## How do I report a bug vs. ask a question vs. disclose a security issue?

- **Security vulnerability** — private advisory, never a public issue. See [SECURITY.md](../SECURITY.md).
- **Reproducible bug** — a bug report issue with repro steps + exact versions.
- **Usage question or half-formed idea** — [Discussions](https://github.com/enchanter-ai/crow/discussions).

The [SUPPORT.md](../SUPPORT.md) page has the exact links for each.

## Is Crow an official Anthropic product?

No. Crow is an independent open-source plugin for [Claude Code](https://github.com/anthropics/claude-code) (Anthropic's CLI). It's published by [enchanter-ai](https://github.com/enchanter-ai) under the MIT license and is not affiliated with, endorsed by, or supported by Anthropic.

## How does Crow resist trust-inflation attacks?

Every identified gaming surface — look-alike edits, gradual-drift warmups, token-splitting / encoding bypass, prompt injection via fetched content, history manipulation, reviewer-fatigue attacks — has a specific counter documented in [THREAT_MODEL.md](../THREAT_MODEL.md). The detectors are deterministic regex/structure checks over the diff; they do not consult an LLM, so content injected into a diff is treated as data, not instruction.

## What do the severities CRITICAL, HIGH, WARNING, and clean mean?

Severity is advisory signal, not a verdict — it reflects which red-flag detectors fired:

- **CRITICAL** — a high-harm detector fired: `exposed_secrets` or `gutted_test`. Stop and review.
- **HIGH** — `weak_crypto` or `wildcard_cors`. Review before committing.
- **WARNING** — `trivial_assertions`, `very_short_file`, `debug_enabled`, or `reverted`. Worth a glance.
- **clean** — no detector fired.

A clean change can still be wrong; a flagged change can be fine. Severity tells you *how much attention to spend*, not what the answer is. Crow assigns no numeric score. Full rubric in [docs/glossary.md](glossary.md).
