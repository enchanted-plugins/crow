# Changelog

All notable changes to `hornet` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Tier-1 governance docs: `SECURITY.md`, `SUPPORT.md`, `CODE_OF_CONDUCT.md`, `CHANGELOG.md`, `THREAT_MODEL.md`.
- `.github/` scaffold: issue templates, PR template, CODEOWNERS, dependabot config.
- Tier-2 docs: `docs/getting-started.md`, `docs/installation.md`, `docs/troubleshooting.md`, `docs/adr/README.md`, `examples/README.md`.

## [1.0.0] — change-trust scoring, Bayesian first line

The current shipped release. See [README.md](README.md) for the complete feature surface.

### Highlights
- 4 plugins covering the change-observation lifecycle.
- 6 named engines (H1 Semantic Diff, H2 Bayesian Trust, H3 Info-Gain, H4 Continuity, H5 Adversarial Robustness, H6 Exponential Strategy Averaging) — formal derivations in [docs/science/README.md](docs/science/README.md).
- 4 managed agents across the three ecosystem tiers.
- Change-tracker hook: semantic diff + trust scoring on every edit.
- Session-memory hook: continuity graph persists across compaction boundaries.
- Attacker-input awareness: trust-gaming surfaces enumerated in [THREAT_MODEL.md](THREAT_MODEL.md).

[Unreleased]: https://github.com/enchanted-plugins/hornet/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/enchanted-plugins/hornet/releases/tag/v1.0.0
