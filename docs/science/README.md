# The Science Behind Crow

Formal mathematical models powering every change-trust engine in Crow.

These aren't abstractions. Every formula maps to running code.

---

## H1. Semantic Diff Analysis

**Problem:** Classify and compress every change into semantic hunks — addition, deletion, modification, or refactor — so the downstream trust engine can weight them correctly.

<p align="center"><img src="../assets/math/h1-classify.svg" alt="classify(f) = config if f in {.json, .yaml, .env}; test if f in {test, spec}; schema if f in {.sql, migration}; source otherwise"></p>

Parses unified diffs hunk-by-hunk. Change type inherits semantics from file extension and path (source, test, config, schema, dependency, docs). Refactor detection uses Python `SequenceMatcher.ratio()` on before/after text with a 0.6 cutoff. Hunks in the same directory cluster into a single logical change. Counts feed a 4-level complexity bucket (none / low / medium / high) that drives the severity of downstream signals.

**Implementation:** `plugins/change-tracker/hooks/post-tool-use/track-change.sh`, `shared/scripts/diff-analyzer.py`

---

## H2. Bayesian Trust Scoring

**Problem:** Estimate the trustworthiness of each file change in real time, so a developer sees a per-file signal after every write.

<p align="center"><img src="../assets/math/h2-bayes.svg" alt="P(theta | D) = P(D | theta) · P(theta) / P(D); P(theta) = Beta(alpha, beta)"></p>

<p align="center"><img src="../assets/math/h2-update.svg" alt="alpha_new = alpha + l; beta_new = beta + (1 - l); trust = alpha / (alpha + beta)"></p>

Beta-Bernoulli conjugate prior starting from Beta(2, 2) (uninformative, centered at 0.5). Each change contributes a likelihood `ℓ` determined by type (test, source, schema, config, dependency, docs) and content signals: gutted tests, weak crypto, exposed secrets, reverts (the last multiplies `ℓ` by 0.5). The posterior mean is the displayed trust score ∈ [0, 1]. Thresholds: critical (< 0.2), low (< 0.4), high (≥ 0.8).

**Implementation:** `plugins/trust-scorer/hooks/post-tool-use/score-change.sh`, `shared/scripts/trust-model.py`

---

## H3. Information-Gain Ordering

**Problem:** Rank which files most need review based on the uncertainty in their trust estimate — review highest-entropy first.

<p align="center"><img src="../assets/math/h3-infogain.svg" alt="IG(X) = H(X) = -p log2(p) - (1-p) log2(1-p)"></p>

Binary entropy: maximum at `p = 0.5` (IG = 1.0), minimum at `p ∈ {0, 1}` (IG = 0). Files with trust closest to 0.5 are those where the model is least certain — they carry the most information per review minute. Since Bash cannot compute logarithms natively, a 19-bucket lookup table in `shared/constants.sh` covers `p` from 0.05 to 0.95 in 5% increments. PreToolUse uses the lookup to pick review order.

**Implementation:** `plugins/decision-gate/hooks/pre-tool-use/gate-change.sh`, `shared/constants.sh`

---

## H4. Session Continuity Graph

**Problem:** Build a reusable cross-session graph of file/cluster/review state before context compaction wipes the transcript.

H4 is structural, not closed-form. The graph `G = (nodes, edges)` has per-file nodes `(file, type, change_count, last_hash, cluster_id)` and per-cluster edges `(cluster_id, file_list)`. The serialized object adds session metadata: `{ ts, session_hash, total_changes, trust_dist, reviews, nodes[0:50], edges[0:20] }`.

The `save-session.sh` hook (PreCompact) gathers the 200 most recent changes from `change-tracker`, 200 file scores from `trust-scorer`, and recent decisions from `decision-gate`. Groups by `cluster_id` to identify architectural regions. Emits both `session-graph.json` and a human-readable `session-summary.md`, both capped at 50 KB for compaction survival. The restorer agent rebuilds context on resume without re-scanning the repo.

**Implementation:** `plugins/session-memory/hooks/pre-compact/save-session.sh`

---

## H5. Adversarial Self-Review

**Problem:** For low-trust changes, surface targeted questions that catch common omissions — gutted tests, removed auth, exposed secrets — before the write executes.

H5 is dispatch logic, not closed-form. Trigger rule: `if trust < 0.4 then emit Q(change_type); exit 0` (advisory only). Cooldown: skip advisory for the next 3 turns after issuing one.

Maps change type to a curated question set: `config → "secrets/env overrides?"`, `test → "assertion weakening?"`, `source → "regression/auth loss?"`, `schema → "reversible/consumer breakage?"`. PreToolUse runs before the write hits disk, giving the developer a last chance to reconsider. The 3-turn cooldown prevents question fatigue.

**Implementation:** `plugins/decision-gate/hooks/pre-tool-use/gate-change.sh`

---

## H6. Exponential Strategy Averaging (EMA Accumulation)

**Problem:** Track cross-session developer preferences — which change types persistently have low trust, which reviewers get overridden — to surface coachable patterns.

<p align="center"><img src="../assets/math/h6-gauss.svg" alt="r_new = alpha · s_current + (1 - alpha) · r_prior; alpha = 0.3"></p>

Per change type (source, test, config, docs, schema, dependency), maintains a running EMA of mean trust (`trust_rate`) and review frequency (`review_rate`). Alpha = 0.3 favors recent signals while preserving history. Chronic patterns — those persistently below 0.4 trust for three or more sessions — emit an alert in `learnings.json` so the next session can surface them.

**Implementation:** `shared/scripts/learnings.py`

---

*Every formula maps to executable code in the enchanted-plugins ecosystem. The math runs.*
