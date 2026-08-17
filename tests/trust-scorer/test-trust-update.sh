#!/usr/bin/env bash
# Test: score-change.sh is STATELESS — the same gutted test flags CRITICAL every
#       time, with no accumulation, no trust.json, and no alpha/beta/posterior.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
TRACK_HOOK="${REPO_ROOT}/plugins/change-tracker/hooks/post-tool-use/track-change.sh"
SCORE_HOOK="${REPO_ROOT}/plugins/trust-scorer/hooks/post-tool-use/score-change.sh"

# Create a gutted test file (all assertions trivial)
TMPDIR_TEST=$(mktemp -d)
TEST_FILE="${TMPDIR_TEST}/auth.test.ts"
printf 'test("x", () => { expect(true); });\n' > "$TEST_FILE"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")

# Clean state aggressively
rm -f "/tmp/crow-changes-${SESSION_HASH}.jsonl"
rm -f "/tmp/crow-flags-${SESSION_HASH}.jsonl"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl.lock"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Edit", tool_input: {file_path: $file}, hook_event_name: "PostToolUse"}')

# Run 3 cycles of track + score; content unchanged — assessment must be identical
for i in 1 2 3; do
  printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/change-tracker" bash "$TRACK_HOOK" 2>/dev/null
  STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/trust-scorer" bash "$SCORE_HOOK" 2>&1 >/dev/null || true)
done

FAIL=0
METRICS="${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl"

# 1. NO trust.json — statelessness
if [[ -f "${REPO_ROOT}/plugins/trust-scorer/state/trust.json" ]]; then
  echo "FAIL: trust.json must NOT be created"; FAIL=1
fi

# 2. Every assessment is CRITICAL gutted_test — no drift from accumulation
CRIT_COUNT=$(grep -c '"severity":"CRITICAL"' "$METRICS" 2>/dev/null || true)
CRIT_COUNT=${CRIT_COUNT:-0}
if [[ "$CRIT_COUNT" -ne 3 ]]; then
  echo "FAIL: expected 3 CRITICAL assessments (stateless, identical), got $CRIT_COUNT"; FAIL=1
fi
if ! grep -q 'gutted_test' "$METRICS" 2>/dev/null; then
  echo "FAIL: gutted_test flag not recorded"; FAIL=1
fi

# 3. No posterior math artifacts anywhere
if grep -qiE '"score"|"alpha"|"beta"|posterior' "$METRICS" 2>/dev/null; then
  echo "FAIL: metrics must not contain score/alpha/beta/posterior"; FAIL=1
fi

# Cleanup
rm -f "$MOCK_TRANSCRIPT"
rm -rf "$TMPDIR_TEST"
rm -f "/tmp/crow-changes-${SESSION_HASH}.jsonl"
rm -f "/tmp/crow-flags-${SESSION_HASH}.jsonl"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl.lock"

exit $FAIL
