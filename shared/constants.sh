#!/usr/bin/env bash
# Crow shared constants — sourced by all hooks and utilities

CROW_VERSION="1.0.0"

# State file names
CROW_CHANGES_FILE="state/changes.jsonl"
CROW_METRICS_FILE="state/metrics.jsonl"
CROW_SESSION_GRAPH="state/session-graph.json"
CROW_SESSION_SUMMARY="state/session-summary.md"
CROW_LEARNINGS_FILE="state/learnings.json"

# Size limits
CROW_MAX_CHANGES_BYTES=10485760       # 10MB
CROW_MAX_METRICS_BYTES=10485760       # 10MB (rotate at 10MB)
CROW_MAX_GRAPH_BYTES=51200            # 50KB (compaction survival)

# NOTE: The former Bayesian trust constants (CROW_TRUST_FILE, CROW_TRUST_HIGH/LOW/
# CRITICAL, CROW_PRIOR_ALPHA/BETA, CROW_LIKELIHOOD_*) and the information-gain
# entropy lookup table (CROW_IG_TABLE_*) were REMOVED. They fed a file-type
# constant into a Beta-Bernoulli update as if it were an observation — the
# "posterior" merely converged to the constant, so the score carried no real
# signal. trust-scorer now emits pure content-derived flags + a severity; see
# plugins/trust-scorer/hooks/post-tool-use/score-change.sh.

# EMA learning rate (Gauss Accumulation)
CROW_GAUSS_ALPHA="0.3"

# Review cooldown
CROW_REVIEW_COOLDOWN_TURNS=3

# Lock config
CROW_LOCK_SUFFIX=".lock"

# Session cache prefix
CROW_CACHE_PREFIX="/tmp/crow-"
