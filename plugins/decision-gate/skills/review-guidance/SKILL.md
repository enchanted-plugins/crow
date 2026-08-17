---
name: review-guidance
description: >
  Use when a review advisory fires or the developer wants to understand what to
  review and why. Explains severity-ordered prioritization of detector-flagged
  changes. Auto-triggers on: "review advisory", "what should I review",
  "which changes matter", "priority review", "adversarial review".
allowed-tools:
  - Read
  - Grep
  - Bash
---

<purpose>
Help the developer focus review on the changes that matter most.
Order flagged changes by severity (CRITICAL → HIGH → WARNING).
Present adversarial questions for each flagged change.
</purpose>

<constraints>
1. NEVER skip adversarial questions for CRITICAL changes.
2. NEVER claim a change is safe. "clean" means no detector fired — not "safe".
3. ALWAYS explain WHY a change was surfaced — name the detector flag that fired.
4. ALWAYS present changes in severity order, not file order.
5. NEVER invent a numeric trust score or information-gain value — Crow computes
   neither. The signal is the flags.
</constraints>

<decision_tree>
IF single file flagged for review:
  → Read the latest `change_flagged` record for it from
    ${CLAUDE_PLUGIN_ROOT}/../trust-scorer/state/metrics.jsonl
    (or the pre-extracted ${CLAUDE_PLUGIN_ROOT}/state/adversary-context.json)
  → Show: file, severity, flags, change type
  → Show adversarial questions (type-specific)
  → "Review this change. The questions above highlight what could go wrong."

IF multiple files need review:
  → Read all `change_flagged` records, latest per file, severity != clean
  → Order by severity (CRITICAL first)
  → Present the top 3 with their flags and adversarial questions
  → "Start with [file1] — it is CRITICAL ([flag])."

IF no files are flagged:
  → "No changes are currently flagged. No detector fired — but that is not proof
     of correctness, only the absence of a matched red-flag pattern."

IF no detector data available:
  → "No detector findings yet. Assessment begins after the first Write/Edit."
</decision_tree>

<severity_ordering_explanation>
Changes are ordered by severity, highest first:
- CRITICAL (exposed_secrets, gutted_test) — review immediately.
- HIGH (weak_crypto, wildcard_cors) — review before continuing.
- WARNING (trivial_assertions, very_short_file, debug_enabled, reverted) — quick look.
Severity is the max over the flags that fired on the change.
</severity_ordering_explanation>

<escalate_to_sonnet>
IF complex multi-file review with several interacting flags:
  "ESCALATE_TO_SONNET: multi-file review needs cross-reference analysis"
IF user needs help understanding adversarial questions:
  "ESCALATE_TO_SONNET: adversarial question context needed"
</escalate_to_sonnet>
