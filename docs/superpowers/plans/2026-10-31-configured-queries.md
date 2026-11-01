# Configured queries implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task by task.

**Goal:** Save query options once and reuse compiled execution with custom functions.

**Architecture:** Keep the global syntax cache independent of function registries. An immutable expression owns its configuration and compiled operations. Per-call overrides inherit omitted defaults without changing the expression.

**Tech stack:** Ruby, RSpec, RBS, Steep, YARD, existing benchmark tools.

**Spec:** [Configured query design](../specs/2026-10-31-configured-queries-design.md).

## Global constraints

- Pure Ruby, MRI 3.3, 3.4, and 4.0, default GC settings.
- Preserve existing public behavior, input adapters, ownership, and error provenance.
- No dependency installation, batch interface, or CLI changes.
- No custom registries in the global cache.

## Review focus

- Partial per-call overrides must retain the other saved options.
- Built-in overrides must disable only their own native shortcut.
- Unknown functions must fail during evaluation, after argument evaluation.
- Suppression must preserve nested callback and adapter failures.
- Concurrent searches must not share mutable invocation state.

### Task 1: Add configured expressions

**Files:** `lib/jmespath.rb`, `lib/jmespath/expression.rb`, `lib/jmespath/options.rb`, `lib/jmespath/plan.rb`, `sig/jmespath.rbs`, internal signatures, and integration specifications.

**Interfaces:** `JMESPath.compile(String, functions:, disable_visit_errors:, cache_expressions:, max_depth:) -> Expression`; `Expression#call` aliases `search`.

- [x] Write failing public tests for saved registries, saved suppression, partial overrides, callable queries, invalid values, and independent cached syntax.
- [x] Run `bundle exec rspec spec/integration/configured_queries_spec.rb` and confirm the added interface fails.
- [x] Add immutable saved configuration to expressions and validate it at compilation.
- [x] Compile operations with the selected registry and error policy; configure fallback evaluation once.
- [x] Add error-provenance, adapter, and concurrent-use regressions through the public interface.
- [x] Update RBS and public documentation with executable examples.
- [x] Run `bundle exec rake` and confirm all correctness and quality gates pass.
- [x] Commit the complete API increment.

### Task 2: Measure configured reuse

**Files:** performance guide and benchmark evidence.

**Interfaces:** Compare saved options with the identical query using per-call options; verify expected results before timing.

- [x] Run five alternating samples on MRI 3.3.11, 3.4.9, and 4.0.9 with default GC settings.
- [x] Measure field traversal, projection, a custom function, built-in override, and suppressed errors.
- [x] Compare default searches with the fixed pre-change revision and investigate material regressions.
- [x] Record runtime metadata, source fingerprints, allocations, timing, and process peak RAM separately.
- [x] Review the implementation and claims; fix verified findings.
- [x] Commit the report after documentation checks pass.
