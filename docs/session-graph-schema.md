# session-graph.json Schema

Written by `plugins/session-memory/hooks/pre-compact/save-session.sh` (V4 Session Continuity Graph).  
Path: `plugins/session-memory/state/session-graph.json`

---

## Top-level object

| Field | Type | Description |
|-------|------|-------------|
| `ts` | string (ISO 8601) | UTC timestamp when the graph was saved |
| `session` | string | MD5 hash of the transcript path; identifies the session |
| `total_changes` | integer | Number of change entries in `change-tracker/state/changes.jsonl` at save time |
| `severity` | object | Summary counts across detector severity bands (see below) |
| `reviews` | integer | Number of `review_advisory` events emitted by decision-gate this session |
| `nodes` | array | File nodes (up to 50); one per distinct file changed (see below) |
| `edges` | array | Cluster edges (up to 20); groups of files changed together (see below) |

---

## `severity` object

Counts are per file, using the most recent detector flag record for each file
(from `trust-scorer`'s session flag cache).

| Field | Type | Description |
|-------|------|-------------|
| `critical` | integer | Count of files whose latest change flagged CRITICAL (`exposed_secrets`, `gutted_test`) |
| `high` | integer | Count of files whose latest change flagged HIGH (`weak_crypto`, `wildcard_cors`) |
| `warning` | integer | Count of files whose latest change flagged WARNING (`trivial_assertions`, `very_short_file`, `debug_enabled`, `reverted`) |

---

## `nodes` array items

Each node represents a distinct file that was changed during the session.  
Built from `change-tracker/state/changes.jsonl`, grouped by `file`, sorted descending by `change_count`.

| Field | Type | Description |
|-------|------|-------------|
| `file` | string | Absolute or relative file path |
| `type` | string | Change type of the first recorded change (e.g. `source_code`, `config_change`, `test_change`, `schema_change`, `dependency_change`, `documentation`) |
| `change_count` | integer | Number of times this file was changed this session |
| `last_hash` | string | Hash of the last change entry for this file |
| `cluster_id` | string | Cluster identifier from the last recorded change (empty string if unclustered) |

---

## `edges` array items

Each edge represents a set of files changed together under the same cluster.  
Only clusters with 2 or more distinct files are included.

| Field | Type | Description |
|-------|------|-------------|
| `cluster` | string | Cluster identifier shared by all files in this edge |
| `files` | array of strings | Unique file paths that share this cluster |

---

## Example

```json
{
  "ts": "2026-04-21T14:32:07Z",
  "session": "a3f9c12b8e4d6f01",
  "total_changes": 12,
  "severity": {
    "critical": 0,
    "high": 2,
    "warning": 1
  },
  "reviews": 3,
  "nodes": [
    {
      "file": "src/auth/middleware.ts",
      "type": "source_code",
      "change_count": 4,
      "last_hash": "d41d8cd98f00b204e9800998ecf8427e",
      "cluster_id": "auth-refactor"
    },
    {
      "file": "src/config/env.ts",
      "type": "config_change",
      "change_count": 2,
      "last_hash": "098f6bcd4621d373cade4e832627b4f6",
      "cluster_id": "auth-refactor"
    },
    {
      "file": "tests/auth.test.ts",
      "type": "test_change",
      "change_count": 1,
      "last_hash": "5d41402abc4b2a76b9719d911017c592",
      "cluster_id": ""
    }
  ],
  "edges": [
    {
      "cluster": "auth-refactor",
      "files": ["src/auth/middleware.ts", "src/config/env.ts"]
    }
  ]
}
```

---

## Notes

- The graph is written atomically via a temp file + `mv` under a file lock.
- At most 50 nodes and 20 edges are stored; the highest-frequency files and clusters are retained.
- The `session` hash is derived from the transcript file path; it is stable within one Claude Code session but changes on session restart.
- The companion `session-summary.md` in the same directory provides a human-readable version of the same data for the restorer agent.
