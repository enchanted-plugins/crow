#!/usr/bin/env python3
"""Raven V1 deep: Semantic diff analysis with hunk classification and complexity scoring.

Analyzes unified diffs to classify changes at the hunk level.
Called by track-change.sh when Python is available and change is large.
Stdlib only — no external dependencies.

Usage: python3 diff-analyzer.py <file_before> <file_after>
Output: JSON to stdout
"""

import difflib
import json
import os
import sys


def classify_hunk(added_lines, removed_lines):
    """Classify a diff hunk by its content pattern."""
    if added_lines and not removed_lines:
        return "addition"
    if removed_lines and not added_lines:
        return "deletion"
    if len(added_lines) == len(removed_lines):
        # Check if it's a rename/refactor (similar structure, different names)
        similarity = difflib.SequenceMatcher(
            None,
            "\n".join(removed_lines),
            "\n".join(added_lines),
        ).ratio()
        if similarity > 0.6:
            return "refactor"
    return "modification"


def analyze_diff(before_path, after_path):
    """Perform semantic diff analysis between two file versions."""
    try:
        with open(before_path, "r", errors="replace") as f:
            before_lines = f.readlines()
    except (OSError, IOError):
        before_lines = []

    try:
        with open(after_path, "r", errors="replace") as f:
            after_lines = f.readlines()
    except (OSError, IOError):
        return {"error": "Cannot read after file: " + after_path}

    diff = list(difflib.unified_diff(before_lines, after_lines, lineterm=""))

    if not diff:
        return {
            "hunks": 0,
            "additions": 0,
            "deletions": 0,
            "modifications": 0,
            "complexity": "none",
            "summary": "No differences detected",
        }

    # Parse hunks from unified diff
    hunks = []
    current_added = []
    current_removed = []
    additions = 0
    deletions = 0

    for line in diff:
        if line.startswith("@@"):
            if current_added or current_removed:
                hunks.append(classify_hunk(current_added, current_removed))
                current_added = []
                current_removed = []
        elif line.startswith("+") and not line.startswith("+++"):
            current_added.append(line[1:])
            additions += 1
        elif line.startswith("-") and not line.startswith("---"):
            current_removed.append(line[1:])
            deletions += 1

    # Final hunk
    if current_added or current_removed:
        hunks.append(classify_hunk(current_added, current_removed))

    # Count hunk types
    type_counts = {}
    for h in hunks:
        type_counts[h] = type_counts.get(h, 0) + 1

    # Complexity heuristic
    num_hunks = len(hunks)
    if num_hunks == 0:
        complexity = "none"
    elif num_hunks == 1:
        complexity = "low"
    elif num_hunks <= 5:
        complexity = "medium"
    else:
        complexity = "high"

    # Generate summary
    parts = []
    if type_counts.get("addition", 0):
        parts.append(f"{type_counts['addition']} addition(s)")
    if type_counts.get("deletion", 0):
        parts.append(f"{type_counts['deletion']} deletion(s)")
    if type_counts.get("modification", 0):
        parts.append(f"{type_counts['modification']} modification(s)")
    if type_counts.get("refactor", 0):
        parts.append(f"{type_counts['refactor']} refactor(s)")

    summary = f"{num_hunks} hunks: " + ", ".join(parts) if parts else "No changes"

    return {
        "hunks": num_hunks,
        "additions": additions,
        "deletions": deletions,
        "modifications": type_counts.get("modification", 0),
        "refactors": type_counts.get("refactor", 0),
        "complexity": complexity,
        "summary": summary,
    }


def main():
    if len(sys.argv) < 3:
        json.dump({"error": "Usage: diff-analyzer.py <before> <after>"}, sys.stdout)
        sys.exit(1)

    before_path = sys.argv[1]
    after_path = sys.argv[2]

    if not os.path.isfile(after_path):
        json.dump({"error": f"File not found: {after_path}"}, sys.stdout)
        sys.exit(1)

    result = analyze_diff(before_path, after_path)
    json.dump(result, sys.stdout)


if __name__ == "__main__":
    main()
