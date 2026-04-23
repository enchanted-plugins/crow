#!/usr/bin/env bash
# Test: score-change.sh updates trust posterior after multiple changes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
TRACK_HOOK="${REPO_ROOT}/plugins/change-tracker/hooks/post-tool-use/track-change.sh"
SCORE_HOOK="${REPO_ROOT}/plugins/trust-scorer/hooks/post-tool-use/score-change.sh"

# Create a test source file
TEST_FILE=$(mktemp --suffix=".ts")
echo "const x = 1;" > "$TEST_FILE"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")

# Clean state aggressively (prior tests may leave residue)
rm -f "/tmp/raven-changes-${SESSION_HASH}.jsonl"
rm -f "/tmp/raven-trust-${SESSION_HASH}.jsonl"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/trust-scorer/state/trust.json"
rm -f "${REPO_ROOT}/plugins/trust-scorer/state/trust.json.tmp"
rm -rf "${REPO_ROOT}/plugins/trust-scorer/state/trust.json.lock"
rm -f "${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl.lock"
# Verify trust.json is truly gone
sync 2>/dev/null || true

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Edit", tool_input: {file_path: $file}, hook_event_name: "PostToolUse"}')

# Run 3 cycles of track + score
for i in 1 2 3; do
  echo "const x = $i;" > "$TEST_FILE"  # Change file content each time
  printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/change-tracker" bash "$TRACK_HOOK" 2>/dev/null
  printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/trust-scorer" bash "$SCORE_HOOK" 2>/dev/null
done

# Verify trust.json has updated posterior
# Note: use first entry in trust.json to avoid path translation issues on Windows/MSYS2
TRUST_FILE="${REPO_ROOT}/plugins/trust-scorer/state/trust.json"

ALPHA=$(jq -r '[to_entries[].value.alpha] | first // 0' "$TRUST_FILE")
BETA=$(jq -r '[to_entries[].value.beta] | first // 0' "$TRUST_FILE")

# After 3 updates from Beta(2,2) with source_code likelihood 0.7:
# alpha should be > 2 (accumulated from prior + 3 * 0.7 = 4.1)
IS_UPDATED=$(jq -n --argjson a "$ALPHA" 'if $a > 3 then 1 else 0 end')

if [[ "$IS_UPDATED" != "1" ]]; then
  echo "FAIL: Alpha should be > 3 after 3 updates, got $ALPHA"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

# Verify the score shifted from the prior
SCORE=$(jq -r '[to_entries[].value.score] | first // 0' "$TRUST_FILE")
PRIOR_SCORE="0.5"
IS_SHIFTED=$(jq -n --argjson s "$SCORE" --argjson p "$PRIOR_SCORE" 'if $s != $p then 1 else 0 end')

if [[ "$IS_SHIFTED" != "1" ]]; then
  echo "FAIL: Trust score should have shifted from prior 0.5, still at $SCORE"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

# Cleanup
rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
rm -f "/tmp/raven-changes-${SESSION_HASH}.jsonl"
rm -f "/tmp/raven-trust-${SESSION_HASH}.jsonl"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/trust-scorer/state/trust.json"
rm -rf "${REPO_ROOT}/plugins/trust-scorer/state/trust.json.lock"
rm -f "${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl.lock"

exit 0
