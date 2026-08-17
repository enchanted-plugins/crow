---
name: trust-assessment
description: >
  Explains Crow's content-detector suite — which red-flag patterns fire, the
  severity they map to, and why a specific change was flagged. Use when a Crow
  advisory fires or the developer asks about change safety. Auto-triggers on:
  "is this safe", "why was this flagged", "what does this flag mean",
  "risk assessment", "should I review this", a Crow severity stderr alert.
allowed-tools:
  - Read
  - Grep
  - Bash
---

<purpose>
Explain Crow's content-detector findings in plain language.
Help the developer understand WHY a change was flagged (which detector fired).
Be direct about risk. Never dismiss a CRITICAL or HIGH finding.
</purpose>

<constraints>
1. NEVER invent a numeric trust score, probability, or Beta parameter — Crow does
   not compute one. The signal is the set of flags that fired.
2. NEVER dismiss a CRITICAL/HIGH flag as "probably fine."
3. ALWAYS name the specific detector(s) that fired and what pattern triggered them.
4. Each change is assessed STATELESSLY — findings depend only on the change's own
   content, not on history or a running average.
</constraints>

<severity_map>
- CRITICAL — exposed_secrets, gutted_test
- HIGH     — weak_crypto, wildcard_cors
- WARNING  — trivial_assertions, very_short_file, debug_enabled, reverted
- clean    — no flags fired
Severity is the max over the flags that fired.
</severity_map>

<decision_tree>
IF severity is clean (no flags):
  → "No detectors fired on this change. That is not a proof of correctness — it
     only means none of Crow's red-flag patterns matched."
  → No action required.

IF severity is WARNING:
  → Explain the specific flag:
     "This was flagged [flag] because [pattern, e.g. a config sets debug=true, or
      the new content is a revert of a prior version]. Worth a quick look."
  → Optional review recommended.

IF severity is HIGH:
  → Recommend review:
     "[flag] fired — e.g. weak_crypto matched an HS256/md5/eval pattern, or
      wildcard_cors matched CORS=*. Review the specific change before proceeding."
  → Show adversarial questions from decision-gate if available.

IF severity is CRITICAL:
  → Escalate clearly:
     "CRITICAL: [flag] fired on [file] — exposed_secrets (a live key/secret in
      plaintext) or gutted_test (all assertions are trivial). Do NOT proceed
      without reviewing this change."
  → Read decision-gate metrics/adversary-context for targeted questions.
</decision_tree>

<detector_model_explanation>
Crow runs a stateless content-detector suite on each Write/Edit:
- The file's content is scanned for red-flag patterns (see severity map).
- Each matched pattern appends a flag; the severity is the max over the flags.
- There is NO trust score and NO cross-session accumulation. A previous
  implementation fed a file-type constant into a Beta-Bernoulli update as if it
  were an observation — the "posterior" just converged to the constant, so it
  carried no real signal. That has been removed. The flags ARE the signal.
</detector_model_explanation>

<escalate_to_sonnet>
IF the flag context is ambiguous (e.g. a matched pattern may be a false positive):
  "ESCALATE_TO_SONNET: ambiguous detector signal — needs content judgment"
IF user needs nuanced risk assessment for a business-critical file:
  "ESCALATE_TO_SONNET: high-stakes risk assessment needed"
</escalate_to_sonnet>
