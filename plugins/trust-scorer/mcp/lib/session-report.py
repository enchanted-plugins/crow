#!/usr/bin/env python3
"""Crow V4 report: Formatted session dashboard.

Reads metrics, changes, trust, and session graph from all plugin state dirs.
Generates a box-drawing formatted text report.
Stdlib only — no external dependencies.

Usage: python3 session-report.py <plugins_dir>
Output: Formatted text report to stdout
"""

import json
import os
import sys
from datetime import datetime


def count_events(filepath, pattern):
    """Count lines matching a pattern in a JSONL file."""
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


def load_json(filepath):
    """Load a JSON file, return empty dict/list on failure."""
    if not os.path.isfile(filepath):
        return {}
    try:
        with open(filepath, "r") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return {}


def load_jsonl_tail(filepath, n=50):
    """Load the last N lines of a JSONL file."""
    if not os.path.isfile(filepath):
        return []
    entries = []
    try:
        with open(filepath, "r") as f:
            lines = f.readlines()
            for line in lines[-n:]:
                line = line.strip()
                if line:
                    try:
                        entries.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
    except IOError:
        pass
    return entries


def generate_report(plugins_dir):
    """Generate the session report from all plugin state."""
    ct_metrics = os.path.join(plugins_dir, "change-tracker", "state", "metrics.jsonl")
    ct_changes = os.path.join(plugins_dir, "change-tracker", "state", "changes.jsonl")
    ts_metrics = os.path.join(plugins_dir, "trust-scorer", "state", "metrics.jsonl")
    ts_trust = os.path.join(plugins_dir, "trust-scorer", "state", "trust.json")
    dg_metrics = os.path.join(plugins_dir, "decision-gate", "state", "metrics.jsonl")
    sm_graph = os.path.join(plugins_dir, "session-memory", "state", "session-graph.json")

    # Counts
    changes_tracked = count_events(ct_metrics, '"change_tracked"')
    trust_scored = count_events(ts_metrics, '"trust_scored"')
    reviews_issued = count_events(dg_metrics, '"review_advisory"')

    # Trust distribution
    trust_data = load_json(ts_trust)
    high = sum(1 for e in trust_data.values() if e.get("score", 0.5) >= 0.8)
    low = sum(1 for e in trust_data.values() if e.get("score", 0.5) < 0.4)
    critical = sum(1 for e in trust_data.values() if e.get("score", 0.5) < 0.2)
    medium = len(trust_data) - high - low

    # Average trust
    scores = [e.get("score", 0.5) for e in trust_data.values()]
    avg_trust = sum(scores) / len(scores) if scores else 0.0

    # Riskiest files
    riskiest = sorted(trust_data.items(), key=lambda x: x[1].get("score", 1.0))[:5]

    # Changes by type
    changes = load_jsonl_tail(ct_changes, 200)
    type_counts = {}
    for c in changes:
        t = c.get("type", "unknown")
        type_counts[t] = type_counts.get(t, 0) + 1

    # Session graph summary
    graph = load_json(sm_graph)
    graph_nodes = len(graph.get("nodes", []))

    now = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

    # Build report
    lines = [
        "",
        "  CROW SESSION REPORT",
        "",
        f"  Trust:    avg {avg_trust:.2f} | {high} high, {medium} medium, {low} low, {critical} critical",
        f"  Changes:  {changes_tracked} tracked | {trust_scored} scored | {reviews_issued} reviewed",
        "",
        "  ── Trust Distribution ─────────────",
    ]

    if trust_data:
        lines.append(f"  High (>0.8):     {high:>4} files")
        lines.append(f"  Medium:          {medium:>4} files")
        lines.append(f"  Low (<0.4):      {low:>4} files")
        lines.append(f"  Critical (<0.2): {critical:>4} files")
    else:
        lines.append("  No trust data yet")

    lines.append("")
    lines.append("  ── Changes by Type ────────────────")
    if type_counts:
        for t, count in sorted(type_counts.items(), key=lambda x: -x[1]):
            lines.append(f"  {t:<22} {count:>4}")
    else:
        lines.append("  No changes tracked yet")

    lines.append("")
    lines.append("  ── Riskiest Files ─────────────────")
    if riskiest:
        for filepath, entry in riskiest:
            score = entry.get("score", 0.5)
            ftype = entry.get("type", "unknown")
            # Truncate long paths
            display = filepath if len(filepath) <= 40 else "..." + filepath[-37:]
            lines.append(f"  {score:.2f}  {display} ({ftype})")
    else:
        lines.append("  No files scored yet")

    lines.append("")
    lines.append("  ── Review Advisories ──────────────")
    if reviews_issued > 0:
        lines.append(f"  Total advisories issued: {reviews_issued}")
    else:
        lines.append("  No review advisories issued")

    lines.append("")
    lines.append(f"  Report generated: {now}")
    lines.append("  Methodology: Bayesian Beta-Bernoulli trust with conservative priors.")
    lines.append("")

    header = "══════════════════════════════════════"
    footer = "══════════════════════════════════════"

    return "\n".join([header] + lines + [footer])


def main():
    if len(sys.argv) < 2:
        print("Usage: session-report.py <plugins_dir>", file=sys.stderr)
        sys.exit(1)

    plugins_dir = sys.argv[1]
    if not os.path.isdir(plugins_dir):
        print(f"Error: {plugins_dir} is not a directory", file=sys.stderr)
        sys.exit(1)

    report = generate_report(plugins_dir)
    print(report)


if __name__ == "__main__":
    main()
