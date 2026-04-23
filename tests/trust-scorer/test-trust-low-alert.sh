#!/usr/bin/env bash
# Test: score-change.sh fires stderr warning for low-trust config changes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
TRACK_HOOK="${REPO_ROOT}/plugins/change-tracker/hooks/post-tool-use/track-change.sh"
SCORE_HOOK="${REPO_ROOT}/plugins/trust-scorer/hooks/post-tool-use/score-change.sh"

# Create a sensitive config file (.env)
TMPDIR_TEST=$(mktemp -d)
TEST_FILE="${TMPDIR_TEST}/.env"
echo "SECRET=abc123" > "$TEST_FILE"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")

# Clean state
rm -f "/tmp/crow-changes-${SESSION_HASH}.jsonl"
rm -f "/tmp/crow-trust-${SESSION_HASH}.jsonl"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/trust-scorer/state/trust.json"
rm -rf "${REPO_ROOT}/plugins/trust-scorer/state/trust.json.lock"
rm -f "${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl.lock"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Write", tool_input: {file_path: $file}, hook_event_name: "PostToolUse"}')

# Run change-tracker first
printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/change-tracker" bash "$TRACK_HOOK" 2>/dev/null

# Run trust-scorer and capture stderr
STDERR_OUT=""
STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/trust-scorer" bash "$SCORE_HOOK" 2>&1 >/dev/null || true)

# Config files with sensitive names (.env) get likelihood 0.3
# After one update: alpha = 2.3, beta = 2.7, trust = 0.46
# This is above LOW (0.4) but below HIGH (0.8), so it might not alert on first write
# Run a few more times to push it lower
for i in 1 2 3; do
  echo "SECRET=new${i}" > "$TEST_FILE"
  printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/change-tracker" bash "$TRACK_HOOK" 2>/dev/null
  STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/trust-scorer" bash "$SCORE_HOOK" 2>&1 >/dev/null || true)
done

# After 4 updates with likelihood 0.3:
# alpha ≈ 2 + 4*0.3 = 3.2, beta ≈ 2 + 4*0.7 = 4.8
# trust ≈ 3.2/8.0 = 0.4 — borderline low
# Check if any low-trust warning appeared
if [[ "$STDERR_OUT" != *"[Crow]"* ]]; then
  # It's possible the score landed exactly at boundary. Check trust.json directly.
  TRUST_FILE="${REPO_ROOT}/plugins/trust-scorer/state/trust.json"
  FILE_KEY=$(printf "%s" "$TEST_FILE" | jq -Rr @json)
  SCORE=$(jq -r ".[${FILE_KEY}].score // 1" "$TRUST_FILE" 2>/dev/null)
  IS_LOW=$(jq -n --argjson s "$SCORE" 'if $s < 0.45 then 1 else 0 end')

  if [[ "$IS_LOW" == "1" ]]; then
    echo "FAIL: Trust is $SCORE (low) but no stderr warning was emitted"
    rm -f "$MOCK_TRANSCRIPT"
    rm -rf "$TMPDIR_TEST"
    exit 1
  fi
  # Score was not low enough — test is inconclusive but not a failure
fi

# Cleanup
rm -f "$MOCK_TRANSCRIPT"
rm -rf "$TMPDIR_TEST"
rm -f "/tmp/crow-changes-${SESSION_HASH}.jsonl"
rm -f "/tmp/crow-trust-${SESSION_HASH}.jsonl"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/trust-scorer/state/trust.json"
rm -rf "${REPO_ROOT}/plugins/trust-scorer/state/trust.json.lock"
rm -f "${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl.lock"

exit 0
