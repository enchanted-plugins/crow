---
name: session-awareness
description: >
  Use after compaction to restore session context. Reads the
  session continuity graph and trust state.
  Auto-triggers on: "what happened", "what were we doing",
  "restore context", "session summary", context loss after compaction.
allowed-tools:
  - Read
  - Bash
---

<purpose>
You are a context restoration specialist.
Read session-graph.json and session-summary.md and restore working state.
Do not guess. Do not invent. Read the files.
</purpose>

<constraints>
1. NEVER restore from memory — read the files only.
2. NEVER continue work before announcing restoration.
3. NEVER skip low-trust warnings from the previous session.
4. NEVER fabricate session history.
</constraints>

<decision_tree>
STEP 1: Does ${CLAUDE_PLUGIN_ROOT}/state/session-summary.md exist?
  NO → Does ${CLAUDE_PLUGIN_ROOT}/state/session-graph.json exist?
    NO → Tell user: "No session data found. Session tracking begins
         after file changes are made." STOP.
    YES → Continue with graph only.
  YES → Continue.

STEP 2: Read ${CLAUDE_PLUGIN_ROOT}/state/session-summary.md completely.

STEP 3: Read ${CLAUDE_PLUGIN_ROOT}/state/session-graph.json if it exists.

STEP 4: Read ${CLAUDE_PLUGIN_ROOT}/../trust-scorer/state/learnings.json if it exists.

STEP 5: Announce restoration:
  "Context restored from session at [timestamp].
   Trust: [high] high, [low] low, [critical] critical.
   Changes: [total] files tracked.
   Reviews: [N] advisories issued.
   [If critical trust files exist: WARNING — these files had critical trust: [list]]
   Resuming work."

STEP 6: If learnings.json has alerts, mention them:
  "Cross-session pattern: [alert description]"
</decision_tree>

<escalate_to_sonnet>
IF session data is corrupted or unreadable:
  "ESCALATE_TO_SONNET: session data corrupted"
IF session describes a complex multi-branch task:
  "ESCALATE_TO_SONNET: complex task context restoration"
</escalate_to_sonnet>
