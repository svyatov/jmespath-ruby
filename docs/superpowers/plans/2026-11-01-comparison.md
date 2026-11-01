# Implementation comparison plan

> For agentic workers: use superpowers:executing-plans for this approved plan.

**Goal:** Measure current Ruby JMESPath implementations and market the verified advantages in the README.

**Architecture:** Extend the existing isolated worker benchmark with provider adapters and a multi-provider runner. Keep library code unchanged.

**Tech stack:** Ruby standard library, existing RSpec and benchmark fixtures, installed MRI and JRuby.

**Spec:** `docs/superpowers/specs/2026-11-01-comparison-design.md`

## Constraints and review focus

Keep runtimes separate, verify results before timing, preserve all failures, and fingerprint inputs.
Distinguish public search from reusable queries and private optimized nodes.
Check unsupported syntax, wrong answers, load failures, stale source hashes, and incomplete comparisons.
Do not add runtime dependencies or change library behavior.

## Task 1: Comparison harness

- [x] Add integration tests proving provider selection, wrong-answer reporting, and continued measurement after a failed case.
- [x] Observe failures before adding provider adapters and the comparison runner.
- [x] Extend `script/support/benchmark_worker.rb` for explicit provider selection and configurable warmup.
- [x] Add `script/compare.rb` for isolated per-round workers, all 18 workloads, public and reusable queries, and fingerprinted raw reports.
- [x] Verify with `bundle exec rspec spec/integration/benchmark_spec.rb` and the full repository checks.
- [x] Commit the harness and tests.

## Task 2: Measurements and README

- [x] Verify upstream installation paths and exact current release artifacts in a temporary directory.
- [x] Run MRI comparisons and a separate JRuby comparison, checking failures before interpreting times.
- [x] Save complete raw reports under `benchmark/results/` and document commands and metadata.
- [x] Rewrite `README.md` with a concise measured table, feature comparison, and qualified migration instructions.
- [x] Update `docs/guides/performance.md` with current results and retained historical evidence.
- [x] Run documentation checks and review every claim against source and raw data.
- [x] Commit the results and documentation.

## Execution record

Approved for implementation in the current session. Use native execution.
Task 1: `bundle exec rake` passed, 3,986 examples, full line and branch coverage, lint, types, CRAP, and documentation checks.
JRuby does not expose MRI's allocation counter. Its reports leave allocations null and retain elapsed time.
The JRuby extension requires `jruby` to initialize its bridge before loading; its removed runtime calls are recorded as failures.
Review found that timed-out workers could corrupt later samples. Commit `2991e75` fixes cleanup; its regression failed before the fix and passed afterward.
The full suite then passed with 3,987 examples and full coverage.
Review identified a conditional in the Jamespath adapter's timed loop. Commit `eab8425` moves mode selection outside the loop.
Jamespath was remeasured against this library with the revised adapter; the README uses that follow-up.
An independent reviewer recomputed the MRI results and confirmed the claims, exclusions, and fingerprints.
The user requested check and cross symbols in place of Yes/No; this overrides the prose skill's default prohibition on emoji.
The independent reviewer verified the JRuby claims, pass counts, loaded source paths, and all sample counts.
Review found platform-dependent glob ordering in source fingerprints. A failing regression reproduced it; explicit sorting now makes future fingerprints portable.
Historical report hashes remain unchanged, with their runtime ordering and harness revisions documented.
Final verification: `bundle exec rake` passed with 3,989 examples, full line and branch coverage, lint, types, CRAP, and documentation checks.
The prose checker reported only the requested check and cross symbols, with no other findings.
