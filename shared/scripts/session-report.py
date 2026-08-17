#!/usr/bin/env python3
"""Crow V4 report: Formatted session dashboard.

Reads metrics, changes, and the session graph from all plugin state dirs.
Reports the content-detector flags raised this session (severity distribution and
flagged files) — NOT a trust score. Crow has no numeric trust value; each change
is assessed statelessly by its own content detectors.

Generates a box-drawing formatted text report.
Stdlib only — no external dependencies.

Usage: python3 session-report.py <plugins_dir>
Output: Formatted text report to stdout
"""

import json
import os
import sys
from datetime import datetime


SEVERITY_ORDER = {"CRITICAL": 0, "HIGH": 1, "WARNING": 2, "clean": 3}


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


def load_flag_events(filepath, n=500):
    """Load `change_flagged` events, most recent record per file."""
    by_file = {}
    for e in load_jsonl_tail(filepath, n):
        if e.get("event") == "change_flagged" and e.get("file"):
            by_file[e["file"]] = e
    return by_file


def generate_report(plugins_dir):
    """Generate the session report from all plugin state."""
    ct_metrics = os.path.join(plugins_dir, "change-tracker", "state", "metrics.jsonl")
    ct_changes = os.path.join(plugins_dir, "change-tracker", "state", "changes.jsonl")
    ts_metrics = os.path.join(plugins_dir, "trust-scorer", "state", "metrics.jsonl")
    dg_metrics = os.path.join(plugins_dir, "decision-gate", "state", "metrics.jsonl")
    sm_graph = os.path.join(plugins_dir, "session-memory", "state", "session-graph.json")

    # Counts
    changes_tracked = count_events(ct_metrics, '"change_tracked"')
    changes_flagged = count_events(ts_metrics, '"change_flagged"')
    reviews_issued = count_events(dg_metrics, '"review_advisory"')

    # Severity distribution (per file, latest flag record)
    by_file = load_flag_events(ts_metrics)
    sev = {"CRITICAL": 0, "HIGH": 0, "WARNING": 0, "clean": 0}
    for e in by_file.values():
        s = e.get("severity", "clean")
        sev[s] = sev.get(s, 0) + 1
    files_assessed = len(by_file)

    # Flagged files (most severe first)
    flagged = [e for e in by_file.values() if e.get("severity", "clean") != "clean"]
    flagged.sort(key=lambda x: (SEVERITY_ORDER.get(x.get("severity"), 9), x.get("file") or ""))
    flagged = flagged[:5]

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
        f"  Flags:    {sev['CRITICAL']} critical, {sev['HIGH']} high, {sev['WARNING']} warning ({files_assessed} files assessed)",
        f"  Changes:  {changes_tracked} tracked | {changes_flagged} assessed | {reviews_issued} reviewed",
        "",
        "  ── Severity Distribution ──────────",
    ]

    if files_assessed:
        clean = sev.get("clean", 0)
        lines.append(f"  CRITICAL: {sev['CRITICAL']:>4} files")
        lines.append(f"  HIGH:     {sev['HIGH']:>4} files")
        lines.append(f"  WARNING:  {sev['WARNING']:>4} files")
        lines.append(f"  clean:    {clean:>4} files")
    else:
        lines.append("  No detector data yet")

    lines.append("")
    lines.append("  ── Changes by Type ────────────────")
    if type_counts:
        for t, count in sorted(type_counts.items(), key=lambda x: -x[1]):
            lines.append(f"  {t:<22} {count:>4}")
    else:
        lines.append("  No changes tracked yet")

    lines.append("")
    lines.append("  ── Flagged Files ──────────────────")
    if flagged:
        for e in flagged:
            filepath = e.get("file", "?")
            sever = e.get("severity", "?")
            flags = ", ".join(e.get("flags", []))
            display = filepath if len(filepath) <= 40 else "..." + filepath[-37:]
            lines.append(f"  {sever:<8}  {display} ({flags})")
    else:
        lines.append("  No changes flagged")

    lines.append("")
    lines.append("  ── Review Advisories ──────────────")
    if reviews_issued > 0:
        lines.append(f"  Total advisories issued: {reviews_issued}")
    else:
        lines.append("  No review advisories issued")

    lines.append("")
    lines.append(f"  Report generated: {now}")
    lines.append("  Methodology: stateless content-detector suite (flags + severity, no score).")
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
