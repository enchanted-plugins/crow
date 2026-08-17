#!/usr/bin/env python3
"""Crow V2b batch: detector-flag roll-up.

Reads the trust-scorer metrics log (`change_flagged` events) and summarizes the
content-detector flags raised this session: counts by severity, flag-type
frequency, and the flagged files (most severe first).

There is NO trust score, no Beta posterior, no per-file accumulation — each change
is assessed statelessly by its own content detectors. This reports what those
detectors actually found.

Called by the /crow:trust command.
Stdlib only — no external dependencies.

Usage: python3 trust-model.py <trust_scorer_metrics_jsonl>
Output: JSON report to stdout
"""

import json
import os
import sys


SEVERITY_ORDER = {"CRITICAL": 0, "HIGH": 1, "WARNING": 2, "clean": 3}


def load_flag_events(path):
    """Load `change_flagged` events from a metrics JSONL file."""
    events = []
    if not path or not os.path.isfile(path):
        return events
    try:
        with open(path, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if obj.get("event") == "change_flagged":
                    events.append(obj)
    except IOError:
        pass
    return events


def latest_per_file(events):
    """Most recent flag record per file (events are in chronological order)."""
    by_file = {}
    for e in events:
        f = e.get("file")
        if f:
            by_file[f] = e
    return by_file


def generate_report(metrics_path):
    """Generate a detector-flag report."""
    events = load_flag_events(metrics_path)

    if not events:
        return {
            "changes_flagged": 0,
            "files_flagged": 0,
            "by_severity": {},
            "flag_frequency": {},
            "flagged_files": [],
            "message": "No detector data available",
        }

    by_file = latest_per_file(events)

    # Severity distribution (per file, latest record)
    by_severity = {"CRITICAL": 0, "HIGH": 0, "WARNING": 0, "clean": 0}
    for e in by_file.values():
        sev = e.get("severity", "clean")
        by_severity[sev] = by_severity.get(sev, 0) + 1

    # Flag-type frequency (per file, latest record)
    flag_frequency = {}
    for e in by_file.values():
        for flag in e.get("flags", []):
            flag_frequency[flag] = flag_frequency.get(flag, 0) + 1

    # Flagged files, most severe first
    flagged = [
        {
            "file": e.get("file"),
            "severity": e.get("severity", "clean"),
            "flags": e.get("flags", []),
            "type": e.get("type", "unknown"),
        }
        for e in by_file.values()
        if e.get("severity", "clean") != "clean"
    ]
    flagged.sort(key=lambda x: (SEVERITY_ORDER.get(x["severity"], 9), x["file"] or ""))

    files_flagged = sum(1 for e in by_file.values() if e.get("severity", "clean") != "clean")

    return {
        "changes_flagged": len(events),
        "files_assessed": len(by_file),
        "files_flagged": files_flagged,
        "by_severity": by_severity,
        "flag_frequency": flag_frequency,
        "flagged_files": flagged,
    }


def main():
    if len(sys.argv) < 2:
        json.dump({"error": "Usage: trust-model.py <trust_scorer_metrics_jsonl>"}, sys.stdout)
        sys.exit(1)

    metrics_path = sys.argv[1]
    report = generate_report(metrics_path)
    json.dump(report, sys.stdout, indent=2)


if __name__ == "__main__":
    main()
