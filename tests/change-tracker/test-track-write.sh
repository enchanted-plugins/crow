#!/usr/bin/env bash
# Test: track-change.sh records a Write operation in changes.jsonl
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/change-tracker/hooks/post-tool-use/track-change.sh"

# Create a test file
TEST_FILE=$(mktemp)
echo "test content" > "$TEST_FILE"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

# Clean session caches
SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")
rm -f "/tmp/raven-changes-${SESSION_HASH}.jsonl"

# Clean plugin state
rm -f "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl.lock"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Write", tool_input: {file_path: $file}, hook_event_name: "PostToolUse"}')

# Run the hook
printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/change-tracker" bash "$HOOK" 2>/dev/null

# Verify exit code was 0
EXIT_CODE=$?
if [[ $EXIT_CODE -ne 0 ]]; then
  echo "FAIL: Hook exited with code $EXIT_CODE"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

# Verify session cache was created
CACHE_FILE="/tmp/raven-changes-${SESSION_HASH}.jsonl"
if [[ ! -f "$CACHE_FILE" ]]; then
  echo "FAIL: Session cache not created at $CACHE_FILE"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT"
  exit 1
fi

# Verify the entry contains expected fields
ENTRY=$(tail -1 "$CACHE_FILE")
if ! printf "%s" "$ENTRY" | jq -e '.file' >/dev/null 2>&1; then
  echo "FAIL: Entry missing 'file' field"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT" "$CACHE_FILE"
  exit 1
fi

if ! printf "%s" "$ENTRY" | jq -e '.type' >/dev/null 2>&1; then
  echo "FAIL: Entry missing 'type' field"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT" "$CACHE_FILE"
  exit 1
fi

if ! printf "%s" "$ENTRY" | jq -e '.hash' >/dev/null 2>&1; then
  echo "FAIL: Entry missing 'hash' field"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT" "$CACHE_FILE"
  exit 1
fi

# Verify metric was logged
METRICS_FILE="${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl"
if [[ ! -f "$METRICS_FILE" ]]; then
  echo "FAIL: Metrics file not created"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT" "$CACHE_FILE"
  exit 1
fi

if ! grep -q '"change_tracked"' "$METRICS_FILE"; then
  echo "FAIL: No change_tracked event in metrics"
  rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT" "$CACHE_FILE"
  exit 1
fi

# Cleanup
rm -f "$TEST_FILE" "$MOCK_TRANSCRIPT" "$CACHE_FILE"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl.lock"

exit 0
