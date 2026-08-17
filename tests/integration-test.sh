#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
cd "$REPO_ROOT"

echo "══════════════════════════════════════"
echo " CROW INTEGRATION TEST"
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

FLAGS_CACHE="/tmp/crow-flags-${SESSION_HASH}.jsonl"
# Latest "SEVERITY (flags)" recorded for a given file this session.
finding_for() {
  grep -F "\"file\":\"$1\"" "$FLAGS_CACHE" 2>/dev/null | tail -1 \
    | jq -r '"\(.severity) (\(.flags | join(", ")))"' 2>/dev/null || echo "?"
}

# ── Turn 1: Claude rewrites src/auth.ts ──
echo "── Turn 1: Write src/auth.ts (source code) ──────"
echo 'export function verifyJWT(t) { if (t.exp < Date.now()) throw new Error("expired"); return t.valid; }' > "$PROJ/src/auth.ts"

run_hook "change-tracker" "hooks/post-tool-use/track-change.sh" "$PROJ/src/auth.ts" "Write" "PostToolUse" >/dev/null
STDERR=$(run_hook "trust-scorer" "hooks/post-tool-use/score-change.sh" "$PROJ/src/auth.ts" "Write" "PostToolUse" 2>&1 >/dev/null)

echo "  Tracked + assessed. Finding: $(finding_for "$PROJ/src/auth.ts")"
[[ -n "$STDERR" ]] && echo "  Alert: $STDERR"
echo ""

# ── Turn 2: Claude edits tests ──
echo "── Turn 2: Edit tests/auth.test.ts (test change) ─"
echo 'import { verifyJWT } from "./auth"; describe("auth", () => { it("verifies", () => { expect(verifyJWT({valid:true,exp:Infinity})).toBe(true); }); });' > "$PROJ/tests/auth.test.ts"

run_hook "change-tracker" "hooks/post-tool-use/track-change.sh" "$PROJ/tests/auth.test.ts" "Edit" "PostToolUse" >/dev/null
STDERR=$(run_hook "trust-scorer" "hooks/post-tool-use/score-change.sh" "$PROJ/tests/auth.test.ts" "Edit" "PostToolUse" 2>&1 >/dev/null)

echo "  Test file assessed. Finding: $(finding_for "$PROJ/tests/auth.test.ts")"
echo ""

# ── Turn 3: Claude writes to .env (SENSITIVE!) ──
echo "── Turn 3: Write .env (SENSITIVE config) ─────────"
printf 'DB_PASSWORD=hunter2\nCORS_ORIGIN=*\nAPI_KEY=sk-live-supersecret123\n' > "$PROJ/.env"

run_hook "change-tracker" "hooks/post-tool-use/track-change.sh" "$PROJ/.env" "Write" "PostToolUse" >/dev/null
STDERR=$(run_hook "trust-scorer" "hooks/post-tool-use/score-change.sh" "$PROJ/.env" "Write" "PostToolUse" 2>&1 >/dev/null)

echo "  .env assessed. Finding: $(finding_for "$PROJ/.env")"
if [[ -n "$STDERR" ]]; then
  echo "  ALERT: $STDERR"
fi
echo ""

# ── Turn 4: Claude writes config/app.json ──
echo "── Turn 4: Write config/app.json (config) ────────"
echo '{"cors":"*","debug":true,"logLevel":"verbose"}' > "$PROJ/config/app.json"

run_hook "change-tracker" "hooks/post-tool-use/track-change.sh" "$PROJ/config/app.json" "Write" "PostToolUse" >/dev/null
run_hook "trust-scorer" "hooks/post-tool-use/score-change.sh" "$PROJ/config/app.json" "Write" "PostToolUse" >/dev/null 2>&1

echo "  Config tracked + assessed. Finding: $(finding_for "$PROJ/config/app.json")"
echo ""

# ── Turn 5: Decision gate on .env (should fire advisory) ──
echo "── Turn 5: Decision gate on .env write ────────────"

GATE_INPUT=$(jq -n \
  --arg t "$TRANSCRIPT" \
  --arg f "$PROJ/.env" \
  --arg cwd "$PROJ" \
  '{transcript_path:$t, cwd:$cwd, tool_name:"Write", tool_input:{file_path:$f}, hook_event_name:"PostToolUse"}')

GATE_STDERR=$(printf "%s" "$GATE_INPUT" | CLAUDE_PLUGIN_ROOT="plugins/decision-gate" bash plugins/decision-gate/hooks/post-tool-use/gate-change.sh 2>&1 >/dev/null)
GATE_EXIT=$?

echo "  Exit code: $GATE_EXIT (0=advisory-only, 2=blocked)"
if [[ -n "$GATE_STDERR" ]]; then
  echo "  ┌──────────────────────────────────"
  echo "$GATE_STDERR" | while IFS= read -r line; do echo "  │ $line"; done
  echo "  └──────────────────────────────────"
else
  echo "  (no advisory — file not flagged under this path)"
fi
echo ""

# ── Turn 6: Decision gate on src/auth.ts (should be quiet) ──
echo "── Turn 6: Decision gate on src/auth.ts ───────────"
rm -f "/tmp/crow-gate-cooldown-${SESSION_HASH}" 2>/dev/null

GATE_INPUT=$(jq -n \
  --arg t "$TRANSCRIPT" \
  --arg f "$PROJ/src/auth.ts" \
  --arg cwd "$PROJ" \
  '{transcript_path:$t, cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$f}, hook_event_name:"PostToolUse"}')

GATE_STDERR=$(printf "%s" "$GATE_INPUT" | CLAUDE_PLUGIN_ROOT="plugins/decision-gate" bash plugins/decision-gate/hooks/post-tool-use/gate-change.sh 2>&1 >/dev/null)

if [[ -z "$GATE_STDERR" ]]; then
  echo "  No advisory (source code file — no detectors fired)."
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
  S_CRIT=$(jq '.severity.critical' plugins/session-memory/state/session-graph.json 2>/dev/null)
  S_HIGH=$(jq '.severity.high' plugins/session-memory/state/session-graph.json 2>/dev/null)
  S_WARN=$(jq '.severity.warning' plugins/session-memory/state/session-graph.json 2>/dev/null)
  echo "  Graph: $TOTAL changes, $NODES file nodes"
  echo "  Severity: $S_CRIT critical, $S_HIGH high, $S_WARN warning"
fi

if [[ -f "plugins/session-memory/state/session-summary.md" ]]; then
  echo "  Session summary saved."
fi
echo ""

# ── Python Reports ──
echo "── Detector Report (trust-model.py) ───────────────"
if command -v python3 >/dev/null 2>&1; then
  python3 shared/scripts/trust-model.py plugins/trust-scorer/state/metrics.jsonl 2>/dev/null
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

# ── Raw detector metrics ──
echo "── trust-scorer metrics.jsonl (change_flagged) ────"
grep '"change_flagged"' plugins/trust-scorer/state/metrics.jsonl 2>/dev/null | head -30
echo ""

# ── Session Summary ──
echo "── session-summary.md ─────────────────────────────"
cat plugins/session-memory/state/session-summary.md 2>/dev/null | head -25
echo ""

# Cleanup
rm -rf "$PROJ" "$TRANSCRIPT"
rm -f plugins/*/state/changes.jsonl plugins/*/state/metrics.jsonl
rm -f plugins/*/state/session-graph.json plugins/*/state/session-summary.md
rm -f plugins/*/state/learnings.json
rm -rf plugins/*/state/*.lock
rm -f /tmp/crow-* 2>/dev/null

echo "══════════════════════════════════════"
echo " INTEGRATION TEST COMPLETE"
echo "══════════════════════════════════════"
