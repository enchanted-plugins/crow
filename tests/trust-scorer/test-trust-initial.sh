#!/usr/bin/env bash
# Test: score-change.sh gives new files a Beta(2,2) prior ≈ 0.5
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
TRACK_HOOK="${REPO_ROOT}/plugins/change-tracker/hooks/post-tool-use/track-change.sh"
SCORE_HOOK="${REPO_ROOT}/plugins/trust-scorer/hooks/post-tool-use/score-change.sh"

# Create a test file
TEST_FILE=$(mktemp)
echo "test content" > "$TEST_FILE"

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

# Run change-tracker first (provides session cache data)
printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/change-tracker" bash "$TRACK_HOOK" 2>/dev/null

# Run trust-scorer
printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/trust-scorer" bash "$SCORE_HOOK" 2>/dev/null

# Verify trust.json was created
TRUST_FILE="${REPO_ROOT}/plugins/trust-scorer/state/trust.json"
if [[ ! -f "$TRUST_FILE" ]]; then
  echo "FAIL: trust.json not created"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

# Verify the trust score is approximately 0.5 (Beta(2,2) + one update)
# After one update with source_code likelihood 0.7:
# alpha = 2 + 0.7 = 2.7, beta = 2 + 0.3 = 2.3
# trust = 2.7 / (2.7 + 2.3) = 0.54
# Note: use first entry in trust.json to avoid path translation issues on Windows/MSYS2
SCORE=$(jq -r '[to_entries[].value.score] | first // 0' "$TRUST_FILE")

# Check score is between 0.4 and 0.7 (reasonable range for first update with neutral prior)
IS_REASONABLE=$(jq -n --argjson s "$SCORE" 'if $s > 0.4 and $s < 0.7 then 1 else 0 end')

if [[ "$IS_REASONABLE" != "1" ]]; then
  echo "FAIL: Initial trust score $SCORE is outside reasonable range (0.4-0.7)"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

# Cleanup
rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
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
