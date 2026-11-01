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
- [ ] Commit the harness and tests.

## Task 2: Measurements and README

- [ ] Verify upstream installation paths and exact current release artifacts in a temporary directory.
- [ ] Run MRI comparisons and a separate JRuby comparison, checking failures before interpreting times.
- [ ] Save complete raw reports under `benchmark/results/` and document commands and metadata.
- [ ] Rewrite `README.md` with a concise measured table, feature comparison, and qualified migration instructions.
- [ ] Update `docs/guides/performance.md` with current results and retained historical evidence.
- [ ] Run documentation checks and review every claim against source and raw data.
- [ ] Commit the results and documentation.

## Execution record

Approved for implementation in the current session. Use native execution.
Task 1: `bundle exec rake` passed, 3,986 examples, full line and branch coverage, lint, types, CRAP, and documentation checks.
JRuby does not expose MRI's allocation counter. Its reports leave allocations null and retain elapsed time.
The JRuby extension requires `jruby` to initialize its bridge before loading; its removed runtime calls are recorded as failures.
