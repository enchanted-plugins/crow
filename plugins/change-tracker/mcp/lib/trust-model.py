#!/usr/bin/env python3
"""Crow V2 batch: Trust recalculation, distribution histogram, and risk report.

Reads trust.json and changes.jsonl, recomputes trust from full change history,
generates a trust distribution summary.
Called by /crow:trust command and session-report.py.
Stdlib only — no external dependencies.

Usage: python3 trust-model.py <trust_json_path> [changes_jsonl_path]
Output: JSON report to stdout
"""

import json
import math
import os
import sys


# Beta(2,2) default prior
DEFAULT_ALPHA = 2
DEFAULT_BETA = 2

# Likelihoods by change type
LIKELIHOODS = {
    "documentation": 0.95,
    "test_change": 0.85,
    "source_code": 0.7,
    "schema_change": 0.55,
    "dependency_change": 0.5,
    "config_change": 0.5,
}

TRUST_HIGH = 0.8
TRUST_LOW = 0.4
TRUST_CRITICAL = 0.2


def beta_mean(alpha, beta):
    """Compute mean of Beta distribution."""
    if alpha + beta == 0:
        return 0.5
    return alpha / (alpha + beta)


def load_trust(path):
    """Load trust.json file."""
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "r") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return {}


def load_changes(path):
    """Load changes.jsonl file."""
    if not path or not os.path.isfile(path):
        return []
    changes = []
    try:
        with open(path, "r") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        changes.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
    except IOError:
        pass
    return changes


def compute_distribution(trust_data):
    """Compute trust score distribution histogram."""
    buckets = {
        "0.0-0.2": 0,
        "0.2-0.4": 0,
        "0.4-0.6": 0,
        "0.6-0.8": 0,
        "0.8-1.0": 0,
    }

    for file_path, entry in trust_data.items():
        score = entry.get("score", 0.5)
        if score < 0.2:
            buckets["0.0-0.2"] += 1
        elif score < 0.4:
            buckets["0.2-0.4"] += 1
        elif score < 0.6:
            buckets["0.4-0.6"] += 1
        elif score < 0.8:
            buckets["0.6-0.8"] += 1
        else:
            buckets["0.8-1.0"] += 1

    return buckets


def find_riskiest(trust_data, limit=10):
    """Find the riskiest files by trust score."""
    entries = []
    for file_path, entry in trust_data.items():
        entries.append({
            "file": file_path,
            "score": round(entry.get("score", 0.5), 4),
            "type": entry.get("type", "unknown"),
            "alpha": round(entry.get("alpha", DEFAULT_ALPHA), 2),
            "beta": round(entry.get("beta", DEFAULT_BETA), 2),
        })

    entries.sort(key=lambda x: x["score"])
    return entries[:limit]


def generate_report(trust_path, changes_path=None):
    """Generate a complete trust analysis report."""
    trust_data = load_trust(trust_path)

    if not trust_data:
        return {
            "files": 0,
            "high_trust": 0,
            "medium_trust": 0,
            "low_trust": 0,
            "critical_trust": 0,
            "distribution": {},
            "riskiest_files": [],
            "avg_trust": 0.0,
            "message": "No trust data available",
        }

    # Count categories
    high = sum(1 for e in trust_data.values() if e.get("score", 0.5) >= TRUST_HIGH)
    low = sum(1 for e in trust_data.values() if e.get("score", 0.5) < TRUST_LOW)
    critical = sum(1 for e in trust_data.values() if e.get("score", 0.5) < TRUST_CRITICAL)
    medium = len(trust_data) - high - low

    # Average trust
    scores = [e.get("score", 0.5) for e in trust_data.values()]
    avg_trust = sum(scores) / len(scores) if scores else 0.5

    # Distribution
    distribution = compute_distribution(trust_data)

    # Riskiest files
    riskiest = find_riskiest(trust_data)

    return {
        "files": len(trust_data),
        "high_trust": high,
        "medium_trust": medium,
        "low_trust": low,
        "critical_trust": critical,
        "avg_trust": round(avg_trust, 4),
        "distribution": distribution,
        "riskiest_files": riskiest,
    }


def main():
    if len(sys.argv) < 2:
        json.dump({"error": "Usage: trust-model.py <trust.json> [changes.jsonl]"}, sys.stdout)
        sys.exit(1)

    trust_path = sys.argv[1]
    changes_path = sys.argv[2] if len(sys.argv) > 2 else None

    report = generate_report(trust_path, changes_path)
    json.dump(report, sys.stdout, indent=2)


if __name__ == "__main__":
    main()
