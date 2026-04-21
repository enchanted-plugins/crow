#!/usr/bin/env python3
"""Hornet V6: Exponential Strategy Averaging — cross-session EMA accumulation.

Accumulates developer preferences across sessions using exponential
moving averages of per-type trust rates and review frequencies.
Not time-critical — called from save-session.sh at compaction time.
Stdlib only — no external dependencies.

Algorithm: Exponential Strategy Averaging
  r_new = alpha * s_current + (1 - alpha) * r_prior
  alpha = 0.3 (learning rate)

Usage: python3 learnings.py <plugins_dir>
Output: Summary JSONL to stdout
"""

import json
import os
import sys
from datetime import datetime


ALPHA = 0.3  # EMA learning rate

CHANGE_TYPES = [
    "source_code",
    "config_change",
    "test_change",
    "documentation",
    "schema_change",
    "dependency_change",
]


def ema(alpha, current, prior):
    """Exponential moving average."""
    return alpha * current + (1 - alpha) * prior


def load_json(filepath):
    """Load JSON file, return empty dict on failure."""
    if not os.path.isfile(filepath):
        return {}
    try:
        with open(filepath, "r") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return {}


def count_pattern(filepath, pattern):
    """Count lines containing a pattern in a file."""
    if not os.path.isfile(filepath):
        return 0
    count = 0
    try:
        with open(filepath, "r") as f:
            for line in f:
                if pattern in line:
                    count += 1
    except IOError:
        pass
    return count


def load_trust_scores_by_type(trust_path):
    """Load trust.json and compute mean trust per change type."""
    trust_data = load_json(trust_path)
    type_scores = {}
    type_counts = {}

    for filepath, entry in trust_data.items():
        ctype = entry.get("type", "source_code")
        score = entry.get("score", 0.5)
        type_scores[ctype] = type_scores.get(ctype, 0.0) + score
        type_counts[ctype] = type_counts.get(ctype, 0) + 1

    means = {}
    for ctype in CHANGE_TYPES:
        if type_counts.get(ctype, 0) > 0:
            means[ctype] = type_scores[ctype] / type_counts[ctype]
        else:
            means[ctype] = None  # No data for this type

    return means


def main():
    if len(sys.argv) < 2:
        print("Usage: learnings.py <plugins_dir>", file=sys.stderr)
        sys.exit(1)

    plugins_dir = sys.argv[1]

    # Paths
    ts_trust = os.path.join(plugins_dir, "trust-scorer", "state", "trust.json")
    ts_metrics = os.path.join(plugins_dir, "trust-scorer", "state", "metrics.jsonl")
    ct_metrics = os.path.join(plugins_dir, "change-tracker", "state", "metrics.jsonl")
    dg_metrics = os.path.join(plugins_dir, "decision-gate", "state", "metrics.jsonl")
    learnings_path = os.path.join(plugins_dir, "trust-scorer", "state", "learnings.json")

    # Load existing learnings
    existing = load_json(learnings_path)
    prev_sessions = existing.get("sessions_recorded", 0)
    new_sessions = prev_sessions + 1

    # Current session data
    changes_tracked = count_pattern(ct_metrics, '"change_tracked"')
    trust_scored = count_pattern(ts_metrics, '"trust_scored"')
    reviews_issued = count_pattern(dg_metrics, '"review_advisory"')

    if changes_tracked == 0 and trust_scored == 0:
        sys.exit(0)

    # Compute per-type trust means for this session
    session_means = load_trust_scores_by_type(ts_trust)

    # Update type priors using EMA
    prev_priors = existing.get("type_priors", {})
    updated_priors = {}

    for ctype in CHANGE_TYPES:
        prev = prev_priors.get(ctype, {})
        prev_rate = prev.get("trust_rate", 0.5)
        prev_review = prev.get("review_rate", 0.0)
        prev_sess = prev.get("sessions", 0)

        current_rate = session_means.get(ctype)
        if current_rate is not None:
            new_rate = ema(ALPHA, current_rate, prev_rate)
        else:
            new_rate = prev_rate  # No data — keep prior

        # Review rate for this type (approximate: reviews / changes for this type)
        # Simple heuristic: if any reviews were issued and this type had low trust, it was likely reviewed
        current_review = 0.0
        if reviews_issued > 0 and current_rate is not None and current_rate < 0.4:
            current_review = 1.0
        new_review = ema(ALPHA, current_review, prev_review)

        updated_priors[ctype] = {
            "trust_rate": round(new_rate, 4),
            "review_rate": round(new_review, 4),
            "sessions": prev_sess + (1 if current_rate is not None else 0),
        }

    # Detect chronic patterns
    alerts = []
    for ctype, data in updated_priors.items():
        if data["trust_rate"] < 0.4 and data["sessions"] >= 3:
            alerts.append(f"chronic:low_trust:{ctype}")
        if data["review_rate"] > 0.7 and data["sessions"] >= 3:
            alerts.append(f"chronic:high_review:{ctype}")

    # Compute averages
    prev_avg_trust = existing.get("avg_trust", 0.5)
    prev_avg_changes = existing.get("avg_changes_per_session", 0.0)

    all_scores = [v for v in session_means.values() if v is not None]
    current_avg_trust = sum(all_scores) / len(all_scores) if all_scores else 0.5

    new_avg_trust = ema(ALPHA, current_avg_trust, prev_avg_trust)
    new_avg_changes = ema(ALPHA, changes_tracked, prev_avg_changes)

    # Build learnings JSON
    timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

    learnings = {
        "version": 1,
        "updated": timestamp,
        "sessions_recorded": new_sessions,
        "type_priors": updated_priors,
        "review_patterns": {
            "total_reviews": existing.get("review_patterns", {}).get("total_reviews", 0) + reviews_issued,
            "reviews_this_session": reviews_issued,
        },
        "alerts": alerts,
        "avg_trust": round(new_avg_trust, 4),
        "avg_changes_per_session": round(new_avg_changes, 1),
    }

    # Write atomically
    learnings_dir = os.path.dirname(learnings_path)
    os.makedirs(learnings_dir, exist_ok=True)
    tmp_path = learnings_path + ".tmp"

    try:
        with open(tmp_path, "w") as f:
            json.dump(learnings, f, indent=2)
        os.replace(tmp_path, learnings_path)
    except IOError as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(0)

    # Output summary
    summary = {
        "event": "learning_updated",
        "ts": timestamp,
        "sessions": new_sessions,
        "types_tracked": len([t for t in updated_priors.values() if t["sessions"] > 0]),
        "alerts": len(alerts),
    }
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
