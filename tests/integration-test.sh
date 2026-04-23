#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
cd "$REPO_ROOT"

echo "══════════════════════════════════════"
echo " RAVEN INTEGRATION TEST"
echo " Full Session Simulation"
echo "══════════════════════════════════════"
echo ""

# Create a mock project
PROJ=$(mktemp -d)
TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"refactor auth"}' > "$TRANSCRIPT"

SESSION_HASH=$(md5sum "$TRANSCRIPT" 2>/dev/null | cut -c1-8)

# Create realistic project files
mkdir -p "$PROJ/src" "$PROJ/tests" "$PROJ/config"
echo 'export function validateToken(t) { return t.valid; }' > "$PROJ/src/auth.ts"
echo 'import { validateToken } from "./auth";' > "$PROJ/tests/auth.test.ts"
echo '{"cors":"localhost:3000","debug":false}' > "$PROJ/config/app.json"
echo 'DB_PASSWORD=hunter2' > "$PROJ/.env"

run_hook() {
  local plugin="$1"
  local hook_path="$2"
  local file_path="$3"
  local tool_name="$4"
  local event="$5"

  local input
  input=$(jq -n \
    --arg t "$TRANSCRIPT" \
    --arg f "$file_path" \
    --arg cwd "$PROJ" \
    '{transcript_path:$t, cwd:$cwd, tool_name:$tool_name, tool_input:{file_path:$f}, hook_event_name:$event}' \
    --arg tool_name "$tool_name" \
    --arg event "$event")

  printf "%s" "$input" | CLAUDE_PLUGIN_ROOT="plugins/$plugin" bash "plugins/$plugin/$hook_path" 2>&1
}

# ── Turn 1: Claude rewrites src/auth.ts ──
echo "── Turn 1: Write src/auth.ts (source code) ──────"
echo 'export function verifyJWT(t) { if (t.exp < Date.now()) throw new Error("expired"); return t.valid; }' > "$PROJ/src/auth.ts"

run_hook "change-tracker" "hooks/post-tool-use/track-change.sh" "$PROJ/src/auth.ts" "Write" "PostToolUse" >/dev/null
STDERR=$(run_hook "trust-scorer" "hooks/post-tool-use/score-change.sh" "$PROJ/src/auth.ts" "Write" "PostToolUse" 2>&1 >/dev/null)

SCORE=$(jq -r '[to_entries[].value.score][0] // "?"' plugins/trust-scorer/state/trust.json 2>/dev/null)
echo "  Tracked + scored. Trust: $SCORE"
[[ -n "$STDERR" ]] && echo "  Alert: $STDERR"
echo ""

# ── Turn 2: Claude edits tests ──
echo "── Turn 2: Edit tests/auth.test.ts (test change) ─"
echo 'import { verifyJWT } from "./auth"; describe("auth", () => { it("verifies", () => { expect(verifyJWT({valid:true,exp:Infinity})).toBe(true); }); });' > "$PROJ/tests/auth.test.ts"

run_hook "change-tracker" "hooks/post-tool-use/track-change.sh" "$PROJ/tests/auth.test.ts" "Edit" "PostToolUse" >/dev/null
STDERR=$(run_hook "trust-scorer" "hooks/post-tool-use/score-change.sh" "$PROJ/tests/auth.test.ts" "Edit" "PostToolUse" 2>&1 >/dev/null)

SCORE=$(jq --arg f "$PROJ/tests/auth.test.ts" -r '.[$f].score // "?"' plugins/trust-scorer/state/trust.json 2>/dev/null)
# Fallback: get the test entry by type
if [[ "$SCORE" == "?" ]]; then
  SCORE=$(jq -r '[to_entries[] | select(.value.type == "test_change")][0].value.score // "?"' plugins/trust-scorer/state/trust.json 2>/dev/null)
fi
echo "  Test file scored. Trust: $SCORE"
echo ""

# ── Turn 3: Claude writes to .env (SENSITIVE!) ──
echo "── Turn 3: Write .env (SENSITIVE config) ─────────"
printf 'DB_PASSWORD=hunter2\nCORS_ORIGIN=*\nAPI_KEY=sk-live-supersecret123\n' > "$PROJ/.env"

run_hook "change-tracker" "hooks/post-tool-use/track-change.sh" "$PROJ/.env" "Write" "PostToolUse" >/dev/null
STDERR=$(run_hook "trust-scorer" "hooks/post-tool-use/score-change.sh" "$PROJ/.env" "Write" "PostToolUse" 2>&1 >/dev/null)

SCORE=$(jq -r '[to_entries[] | select(.value.type == "config_change")][0].value.score // "?"' plugins/trust-scorer/state/trust.json 2>/dev/null)
echo "  .env scored. Trust: $SCORE"
if [[ -n "$STDERR" ]]; then
  echo "  ALERT: $STDERR"
fi
echo ""

# ── Turn 4: Claude writes config/app.json ──
echo "── Turn 4: Write config/app.json (config) ────────"
echo '{"cors":"*","debug":true,"logLevel":"verbose"}' > "$PROJ/config/app.json"

run_hook "change-tracker" "hooks/post-tool-use/track-change.sh" "$PROJ/config/app.json" "Write" "PostToolUse" >/dev/null
run_hook "trust-scorer" "hooks/post-tool-use/score-change.sh" "$PROJ/config/app.json" "Write" "PostToolUse" >/dev/null 2>&1

echo "  Config tracked + scored."
echo ""

# ── Turn 5: Decision gate on .env (should fire advisory) ──
echo "── Turn 5: Decision gate on .env write ────────────"

GATE_INPUT=$(jq -n \
  --arg t "$TRANSCRIPT" \
  --arg f "$PROJ/.env" \
  --arg cwd "$PROJ" \
  '{transcript_path:$t, cwd:$cwd, tool_name:"Write", tool_input:{file_path:$f}, hook_event_name:"PreToolUse"}')

GATE_STDERR=$(printf "%s" "$GATE_INPUT" | CLAUDE_PLUGIN_ROOT="plugins/decision-gate" bash plugins/decision-gate/hooks/pre-tool-use/gate-change.sh 2>&1 >/dev/null)
GATE_EXIT=$?

echo "  Exit code: $GATE_EXIT (0=advisory-only, 2=blocked)"
if [[ -n "$GATE_STDERR" ]]; then
  echo "  ┌──────────────────────────────────"
  echo "$GATE_STDERR" | while IFS= read -r line; do echo "  │ $line"; done
  echo "  └──────────────────────────────────"
else
  echo "  (no advisory — file not in trust.json under this path)"
fi
echo ""

# ── Turn 6: Decision gate on src/auth.ts (should be quiet) ──
echo "── Turn 6: Decision gate on src/auth.ts ───────────"
rm -f "/tmp/crow-gate-cooldown-${SESSION_HASH}" 2>/dev/null

GATE_INPUT=$(jq -n \
  --arg t "$TRANSCRIPT" \
  --arg f "$PROJ/src/auth.ts" \
  --arg cwd "$PROJ" \
  '{transcript_path:$t, cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$f}, hook_event_name:"PreToolUse"}')

GATE_STDERR=$(printf "%s" "$GATE_INPUT" | CLAUDE_PLUGIN_ROOT="plugins/decision-gate" bash plugins/decision-gate/hooks/pre-tool-use/gate-change.sh 2>&1 >/dev/null)

if [[ -z "$GATE_STDERR" ]]; then
  echo "  No advisory (source code file — moderate/high trust)."
else
  echo "  Advisory: $GATE_STDERR"
fi
echo ""

# ── Compaction: session-memory ──
echo "── Compaction: Session Memory Saves ───────────────"
COMPACT_INPUT=$(jq -n --arg t "$TRANSCRIPT" '{transcript_path:$t, cwd:"/tmp", hook_event_name:"PreCompact"}')

printf "%s" "$COMPACT_INPUT" | CLAUDE_PLUGIN_ROOT="plugins/session-memory" bash plugins/session-memory/hooks/pre-compact/save-session.sh 2>/dev/null

if [[ -f "plugins/session-memory/state/session-graph.json" ]]; then
  NODES=$(jq '.nodes | length' plugins/session-memory/state/session-graph.json 2>/dev/null)
  TOTAL=$(jq '.total_changes' plugins/session-memory/state/session-graph.json 2>/dev/null)
  T_HIGH=$(jq '.trust.high' plugins/session-memory/state/session-graph.json 2>/dev/null)
  T_LOW=$(jq '.trust.low' plugins/session-memory/state/session-graph.json 2>/dev/null)
  T_CRIT=$(jq '.trust.critical' plugins/session-memory/state/session-graph.json 2>/dev/null)
  echo "  Graph: $TOTAL changes, $NODES file nodes"
  echo "  Trust: $T_HIGH high, $T_LOW low, $T_CRIT critical"
fi

if [[ -f "plugins/session-memory/state/session-summary.md" ]]; then
  echo "  Session summary saved."
fi
echo ""

# ── Python Reports ──
echo "── Trust Report (trust-model.py) ──────────────────"
if command -v python3 >/dev/null 2>&1; then
  python3 shared/scripts/trust-model.py plugins/trust-scorer/state/trust.json 2>/dev/null
else
  echo "  (python3 not available)"
fi
echo ""

echo "── Session Dashboard (session-report.py) ──────────"
if command -v python3 >/dev/null 2>&1; then
  python3 shared/scripts/session-report.py plugins/ 2>/dev/null
else
  echo "  (python3 not available)"
fi
echo ""

# ── Raw trust.json ──
echo "── trust.json ─────────────────────────────────────"
jq '.' plugins/trust-scorer/state/trust.json 2>/dev/null | head -30
echo ""

# ── Session Summary ──
echo "── session-summary.md ─────────────────────────────"
cat plugins/session-memory/state/session-summary.md 2>/dev/null | head -25
echo ""

# Cleanup
rm -rf "$PROJ" "$TRANSCRIPT"
rm -f plugins/*/state/changes.jsonl plugins/*/state/metrics.jsonl
rm -f plugins/*/state/trust.json plugins/*/state/trust.json.tmp
rm -f plugins/*/state/session-graph.json plugins/*/state/session-summary.md
rm -f plugins/*/state/learnings.json
rm -rf plugins/*/state/*.lock
rm -f /tmp/crow-* 2>/dev/null

echo "══════════════════════════════════════"
echo " INTEGRATION TEST COMPLETE"
echo "══════════════════════════════════════"
