# Vigil — What You Need To Know

You have Vigil installed. It watches every file you write or edit and scores your changes for trust.

## What's happening behind the scenes

Every time you use Write, Edit, or MultiEdit:
1. **change-tracker** records the file, classifies the change type, and clusters related edits
2. **trust-scorer** computes a Bayesian trust score for that file (0.0 = dangerous, 1.0 = safe)
3. **decision-gate** may surface a review advisory before the write if trust is low

Before compaction, **session-memory** saves the full session state so context survives.

## Trust scores — what they mean

| Score | Meaning | Your action |
|-------|---------|-------------|
| 0.8+ | High trust — safe pattern | No review needed |
| 0.4–0.8 | Moderate — uncertain | Optional review |
| 0.2–0.4 | Low — suspicious pattern | Review before continuing |
| < 0.2 | Critical — likely wrong | Stop and explain to the developer |

Sensitive files (.env, credentials, secrets) start with lower trust. Test files that delete assertions drop fast. Config changes with wildcards (CORS=*) are flagged.

## What you MUST do

1. **When you see `[Vigil]` in stderr**: Acknowledge it to the developer. Don't ignore it. Say what Vigil flagged and why.

2. **When trust drops below 0.4**: Pause and explain what you changed and why. Don't keep writing to that file without addressing the concern.

3. **When trust drops below 0.2**: Stop writing to that file. Tell the developer: "Vigil flagged this as critical. Here's what I changed and what could go wrong."

4. **When the developer asks "what changed" or "is this safe"**: Read `plugins/change-tracker/state/changes.jsonl` and `plugins/trust-scorer/state/trust.json`. Give a semantic summary, not a file list.

5. **After compaction**: Read `plugins/session-memory/state/session-summary.md` to restore context. Tell the developer what happened before compaction.

## Commands the developer can use

- `/vigil:changes` — what files were touched, grouped by type
- `/vigil:trust` — trust scores sorted riskiest-first
- `/vigil:review` — what to review, ranked by information gain
- `/vigil:session` — full session dashboard

## What NOT to do

- Don't suppress or dismiss Vigil warnings
- Don't modify Vigil state files
- Don't delete test assertions to make tests pass — Vigil will catch it
- Don't add wildcard CORS, disable auth, or remove rate limiters without explaining why
