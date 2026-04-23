#!/usr/bin/env bash
# Test: track-change.sh correctly classifies change types by file extension
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/change-tracker/hooks/post-tool-use/track-change.sh"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")
CACHE_FILE="/tmp/crow-changes-${SESSION_HASH}.jsonl"

# Clean state
rm -f "$CACHE_FILE"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl.lock"

# Test cases: file extension → expected type
declare -A TESTS
TMPDIR_TEST=$(mktemp -d)

# Create test files with specific names
echo "code" > "${TMPDIR_TEST}/app.ts"
echo '{}' > "${TMPDIR_TEST}/config.json"
echo "# readme" > "${TMPDIR_TEST}/README.md"
echo "test" > "${TMPDIR_TEST}/auth.test.ts"
echo "CREATE TABLE" > "${TMPDIR_TEST}/001_init.sql"
echo '{"name":"test"}' > "${TMPDIR_TEST}/package.json"

TESTS["${TMPDIR_TEST}/app.ts"]="source_code"
TESTS["${TMPDIR_TEST}/config.json"]="config_change"
TESTS["${TMPDIR_TEST}/README.md"]="documentation"
TESTS["${TMPDIR_TEST}/auth.test.ts"]="test_change"
TESTS["${TMPDIR_TEST}/001_init.sql"]="schema_change"
TESTS["${TMPDIR_TEST}/package.json"]="dependency_change"

FAILED=0

for FILE_PATH in "${!TESTS[@]}"; do
  EXPECTED="${TESTS[$FILE_PATH]}"

  INPUT=$(jq -n \
    --arg transcript "$MOCK_TRANSCRIPT" \
    --arg file "$FILE_PATH" \
    '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Write", tool_input: {file_path: $file}, hook_event_name: "PostToolUse"}')

  printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/change-tracker" bash "$HOOK" 2>/dev/null

  ACTUAL=$(tail -1 "$CACHE_FILE" | jq -r '.type' 2>/dev/null)

  if [[ "$ACTUAL" != "$EXPECTED" ]]; then
    BASENAME=$(basename "$FILE_PATH")
    echo "FAIL: $BASENAME classified as '$ACTUAL', expected '$EXPECTED'"
    FAILED=1
  fi
done

# Cleanup
rm -f "$MOCK_TRANSCRIPT" "$CACHE_FILE"
rm -rf "$TMPDIR_TEST"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl.lock"

exit $FAILED
