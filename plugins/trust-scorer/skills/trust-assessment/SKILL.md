---
name: trust-assessment
description: >
  Use when trust alerts fire or developer asks about change safety.
  Auto-triggers on: "is this safe", "trust score", "how confident",
  "risk assessment", "should I review this", low trust stderr alert.
allowed-tools:
  - Read
  - Grep
  - Bash
---

<purpose>
Explain the Bayesian trust model in plain language.
Help the developer understand WHY a change is trusted or not.
Be direct about risk. Never dismiss low trust scores.
</purpose>

<constraints>
1. NEVER override trust scores with opinion — the math is the source of truth.
2. NEVER dismiss a low trust score as "probably fine."
3. ALWAYS explain what factors drove the score (change type, prior history, revert detection).
4. ALWAYS show the Beta parameters (alpha, beta) when explaining scores.
</constraints>

<decision_tree>
IF trust is high (>= 0.8):
  → Reassure with evidence: "This file has been consistently modified with safe patterns.
     Beta(alpha, beta) = score. Change type: [type]."
  → No action needed.

IF trust is medium (0.4 - 0.8):
  → Explain contributing factors:
     "Trust is moderate because [change type] has a neutral prior.
      After [N] updates, the posterior is Beta([alpha], [beta]) = [score]."
  → Optional review recommended.

IF trust is low (0.2 - 0.4):
  → Recommend specific review:
     "This file scored [score] due to [reason: config change / dependency / revert].
      Review the specific change before proceeding."
  → Show adversarial questions from decision-gate if available.

IF trust is critical (< 0.2):
  → Escalate clearly:
     "CRITICAL: [file] scored [score]. This typically means [explanation].
      Do NOT proceed without reviewing this change."
  → Read decision-gate metrics for adversarial questions.
</decision_tree>

<trust_model_explanation>
Vigil uses Beta-Bernoulli conjugate priors for trust:
- Each file starts at Beta(2, 2) — a mildly uncertain prior (mean = 0.5)
- Each change updates: alpha += likelihood, beta += (1 - likelihood)
- Likelihood depends on change type: docs (0.95), tests (0.85), source (0.7), config (0.3-0.5)
- Trust score = alpha / (alpha + beta)
- More changes → narrower posterior → higher confidence in the score
</trust_model_explanation>

<escalate_to_sonnet>
IF trust pattern is ambiguous or contradictory:
  "ESCALATE_TO_SONNET: ambiguous trust signals"
IF user needs nuanced risk assessment for business-critical file:
  "ESCALATE_TO_SONNET: high-stakes risk assessment needed"
</escalate_to_sonnet>
