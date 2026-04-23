#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
cd "$REPO_ROOT"

# Clean all state
rm -f plugins/*/state/changes.jsonl plugins/*/state/metrics.jsonl
rm -f plugins/*/state/trust.json plugins/*/state/trust.json.tmp
rm -f plugins/*/state/session-graph.json plugins/*/state/session-summary.md
rm -f plugins/*/state/learnings.json
rm -rf plugins/*/state/*.lock
rm -f /tmp/raven-* 2>/dev/null

# Create mock session
PROJ=$(mktemp -d)
TRANSCRIPT=$(mktemp)
echo '{"role":"user"}' > "$TRANSCRIPT"
SESSION_HASH=$(md5sum "$TRANSCRIPT" 2>/dev/null | cut -c1-8)

# Create a realistic project
mkdir -p "$PROJ/src" "$PROJ/tests"
cat > "$PROJ/src/auth.ts" << 'SRC'
import { verify } from "jsonwebtoken";

export function validateToken(token: string, secret: string) {
  const decoded = verify(token, secret, { algorithms: ["RS256"] });
  if (decoded.exp < Date.now() / 1000) throw new Error("Token expired");
  return decoded;
}

export function rateLimit(req: Request, limit = 100) {
  const ip = req.headers["x-forwarded-for"];
  if (requestCount(ip) > limit) throw new Error("Rate limited");
  return true;
}
SRC

cat > "$PROJ/tests/auth.test.ts" << 'TEST'
import { validateToken, rateLimit } from "../src/auth";

describe("validateToken", () => {
  it("rejects expired tokens", () => {
    expect(() => validateToken(expiredToken, secret)).toThrow("Token expired");
  });
  it("rejects tampered tokens", () => {
    expect(() => validateToken(tamperedToken, secret)).toThrow();
  });
  it("accepts valid tokens", () => {
    const result = validateToken(validToken, secret);
    expect(result.sub).toBe("user-123");
  });
});

describe("rateLimit", () => {
  it("blocks after 100 requests", () => {
    expect(() => rateLimit(req101)).toThrow("Rate limited");
  });
});
TEST

echo 'DATABASE_URL=postgres://prod:secret@db.internal/app' > "$PROJ/.env"

# Helper to run hooks
run_post() {
  local file="$1" tool="${2:-Write}"
  local input
  input=$(jq -n --arg t "$TRANSCRIPT" --arg f "$file" --arg cwd "$PROJ" --arg tool "$tool" \
    '{transcript_path:$t, cwd:$cwd, tool_name:$tool, tool_input:{file_path:$f}, hook_event_name:"PostToolUse"}')
  printf "%s" "$input" | CLAUDE_PLUGIN_ROOT="plugins/change-tracker" bash plugins/change-tracker/hooks/post-tool-use/track-change.sh 2>/dev/null
  printf "%s" "$input" | CLAUDE_PLUGIN_ROOT="plugins/trust-scorer" bash plugins/trust-scorer/hooks/post-tool-use/score-change.sh
}

run_pre() {
  local file="$1"
  local input
  input=$(jq -n --arg t "$TRANSCRIPT" --arg f "$file" --arg cwd "$PROJ" \
    '{transcript_path:$t, cwd:$cwd, tool_name:"Write", tool_input:{file_path:$f}, hook_event_name:"PreToolUse"}')
  printf "%s" "$input" | CLAUDE_PLUGIN_ROOT="plugins/decision-gate" bash plugins/decision-gate/hooks/pre-tool-use/gate-change.sh
}

# ═══════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════"
echo " RAVEN DEMO — Catching Bad AI Changes"
echo "═══════════════════════════════════════════════"
echo ""
echo " Scenario: Claude is asked to 'fix the auth tests'."
echo " Watch what happens when it takes shortcuts."
echo ""
echo "───────────────────────────────────────────────"

# ── TURN 1: Good change — rename function ──
echo ""
echo " TURN 1: Claude renames validateToken → verifyJWT"
echo "         (safe refactor, same logic)"
echo ""

sed -i 's/validateToken/verifyJWT/g' "$PROJ/src/auth.ts"

printf "  PostToolUse  → " ; run_post "$PROJ/src/auth.ts" "Edit" 2>&1 | grep -o '\[Crow\].*' || true
echo ""

# ── TURN 2: Good change — update test imports ──
echo " TURN 2: Claude updates test imports to match"
echo ""

sed -i 's/validateToken/verifyJWT/g' "$PROJ/tests/auth.test.ts"

printf "  PostToolUse  → " ; run_post "$PROJ/tests/auth.test.ts" "Edit" 2>&1 | grep -o '\[Crow\].*' || true
echo ""

# ── TURN 3: BAD — Claude deletes test assertions to make tests pass ──
echo " TURN 3: Claude DELETES test assertions to make tests pass"
echo "         (this is the #1 anti-pattern — Issue #18541)"
echo ""

cat > "$PROJ/tests/auth.test.ts" << 'BADTEST'
import { verifyJWT } from "../src/auth";

describe("verifyJWT", () => {
  it("works", () => {
    expect(true).toBe(true);
  });
});
BADTEST

printf "  PostToolUse  → " ; run_post "$PROJ/tests/auth.test.ts" "Write" 2>&1 | grep -o '\[Crow\].*' || true
echo ""

# ── TURN 4: BAD — Claude removes the rate limiter ──
echo " TURN 4: Claude REMOVES the rate limiter entirely"
echo "         ('simplifying' the code)"
echo ""

cat > "$PROJ/src/auth.ts" << 'BADCODE'
import { verify } from "jsonwebtoken";

export function verifyJWT(token: string, secret: string) {
  return verify(token, secret);
}
BADCODE

printf "  PostToolUse  → " ; run_post "$PROJ/src/auth.ts" "Write" 2>&1 | grep -o '\[Crow\].*' || true
echo ""

# ── TURN 5: BAD — Claude changes JWT algorithm from RS256 to HS256 ──
echo " TURN 5: Claude changes JWT from RS256 → HS256"
echo "         (security downgrade — asymmetric to symmetric)"
echo ""

cat > "$PROJ/src/auth.ts" << 'WORSECODE'
import { verify } from "jsonwebtoken";

export function verifyJWT(token: string, secret: string) {
  return verify(token, secret, { algorithms: ["HS256"] });
}
WORSECODE

printf "  PostToolUse  → " ; run_post "$PROJ/src/auth.ts" "Write" 2>&1 | grep -o '\[Crow\].*' || true
echo ""

# ── TURN 6: BAD — Claude writes CORS_ORIGIN=* to .env ──
echo " TURN 6: Claude adds CORS_ORIGIN=* to .env"
echo "         (wildcard CORS in production)"
echo ""

printf 'DATABASE_URL=postgres://prod:secret@db.internal/app\nCORS_ORIGIN=*\n' > "$PROJ/.env"

printf "  PostToolUse  → " ; run_post "$PROJ/.env" "Write" 2>&1 | grep -o '\[Crow\].*' || true
echo ""

# ── TURN 7: ANOTHER BAD .env change — pushing trust lower ──
echo " TURN 7: Claude adds API key directly in .env"
echo ""

printf 'DATABASE_URL=postgres://prod:secret@db.internal/app\nCORS_ORIGIN=*\nSTRIPE_SECRET_KEY=sk_live_abc123\n' > "$PROJ/.env"

printf "  PostToolUse  → " ; run_post "$PROJ/.env" "Write" 2>&1 | grep -o '\[Crow\].*' || true
echo ""

# ── DECISION GATE: Before next .env write ──
echo "───────────────────────────────────────────────"
echo ""
echo " Claude tries to write .env AGAIN..."
echo " Decision gate fires BEFORE the write:"
echo ""
rm -f "/tmp/raven-gate-cooldown-${SESSION_HASH}" 2>/dev/null

printf "  PreToolUse   → " ; run_pre "$PROJ/.env" 2>&1 | grep -o '\[Crow\].*' || true
echo ""

# ── SHOW THE TRUST TABLE ──
echo "───────────────────────────────────────────────"
echo ""
echo " FINAL TRUST STATE"
echo ""

jq -r 'to_entries | sort_by(.value.score) | .[] |
  "  " + (.value.score * 100 | floor / 100 | tostring | .[0:4]) +
  "  " + (.value.type | .[0:18]) +
  "  " + (.key | split("/") | last)' \
  plugins/trust-scorer/state/trust.json 2>/dev/null

echo ""

# ── SHOW SESSION SUMMARY ──
echo "───────────────────────────────────────────────"
echo ""
echo " SESSION SUMMARY (what survives compaction)"
echo ""

COMPACT_INPUT=$(jq -n --arg t "$TRANSCRIPT" '{transcript_path:$t, cwd:"/tmp", hook_event_name:"PreCompact"}')
printf "%s" "$COMPACT_INPUT" | CLAUDE_PLUGIN_ROOT="plugins/session-memory" bash plugins/session-memory/hooks/pre-compact/save-session.sh 2>/dev/null

if [[ -f "plugins/session-memory/state/session-summary.md" ]]; then
  head -20 plugins/session-memory/state/session-summary.md | sed 's/^/  /'
fi

echo ""
echo "═══════════════════════════════════════════════"
echo " Without Crow: developer rubber-stamps all 7."
echo " With Crow: turns 3-7 are flagged immediately."
echo "═══════════════════════════════════════════════"
echo ""

# Cleanup
rm -rf "$PROJ" "$TRANSCRIPT"
rm -f plugins/*/state/changes.jsonl plugins/*/state/metrics.jsonl
rm -f plugins/*/state/trust.json plugins/*/state/trust.json.tmp
rm -f plugins/*/state/session-graph.json plugins/*/state/session-summary.md
rm -f plugins/*/state/learnings.json
rm -rf plugins/*/state/*.lock
rm -f /tmp/raven-* 2>/dev/null
