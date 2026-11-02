# Evaluation tracing implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Explain null fields, rejected filter items, and omitted projection results through bounded, explicit traced evaluation.

**Architecture:** A private traced evaluator reuses evaluator semantics and overrides only operations that need diagnostics or iteration context. A per-call collector owns events, logical operation IDs, reference counters, and finalization. Ordinary search retains its execution path.

**Tech Stack:** Ruby 3.3+, standard-library synchronization, RSpec, RBS, Steep, YARD, and the installed benchmark harness. No added dependencies.

**Spec:** [Approved design](../specs/2026-11-02-evaluation-tracing-design.md).

## Global constraints

- Add `Expression#trace(data, options = {}, limit: 1000, **keywords)` after `require "jmespath"`.
- Require a positive Integer limit and raise ArgumentError before consuming input when the limit is invalid.
- Return a frozen hash with exactly `:value`, `:events`, and `:truncated`.
- Each event has exactly `:type`, `:operation_id`, `:context`, and `:details`.
- Keys use symbols; event types and detail enum values use strings.
- Each frame has exactly `:operation_id` and `:index`.
- Retain the first `limit` events in observed evaluation order.
- Preserve selected input object identity and ordinary mutability; never freeze or copy the returned value for tracing.
- Preserve evaluation order, selected object identity, conversions, callbacks, exceptions, and suppression behavior.
- Exclude automatic logging, retries, query reruns, complete execution histories, input snapshots, and original-document provenance.
- Preserve dependencies, imported fixtures, and ordinary search defaults.
- Preserve the unrelated untracked `oss-audit-report.md`.

## Review focus

- R1: Hash defaults and custom methods must not receive extra calls to classify a null field. Test in Task 2.
- R2: Filters must finish all conditions before projecting, retaining original indexes after exclusions. Test in Task 3.
- R3: Escaped references must evaluate after trace completion without retaining or changing completed diagnostic state. Test in Task 4.
- R4: Application exceptions resembling library failures must retain identity and backtraces under suppression. Test in Task 4.
- R5: Concurrent reference calls need separate contexts and an exact shared limit without serializing callbacks. Test in Task 4.

## File map

| File | Responsibility |
| --- | --- |
| `lib/jmespath/expression.rb` | Public trace entry point, option handling, input loading, and finalization |
| `lib/jmespath.rb` | Load private trace components |
| `lib/jmespath/explanation.rb` | Share logical traversal ordering if needed, without changing public explanations |
| `lib/jmespath/tracing/collector.rb` | Bounded event storage, iteration contexts, reference counters, and report finalization |
| `lib/jmespath/tracing/evaluator.rb` | Evaluator subclass for trace-aware fields, projections, filters, and references |
| `lib/jmespath/tracing/field_lookup.rb` | Lookup with conservative reason classification and unchanged observable access |
| `sig/jmespath.rbs` | Public trace records and method declaration |
| `sig/internal/tracing.rbs` | Private tracing declarations |
| `spec/integration/evaluation_tracing_spec.rb` | Public result, schema, option, and limit contract |
| `spec/integration/evaluation_tracing_events_spec.rb` | Null-field reasons, item contexts, operation IDs, and event order |
| `spec/integration/evaluation_tracing_behavior_spec.rb` | Callback, conversion, exception, and execution parity |
| `spec/integration/evaluation_tracing_concurrency_spec.rb` | Concurrent calls, reentry, and escaped references |
| `spec/integration/traced_compliance_spec.rb` | Trace evaluation against unchanged pinned fixtures |
| `spec/integration/evaluation_tracing_regressions_spec.rb` | Independent review regressions |
| `spec/unit/tracing_collector_spec.rb` | Collector limits, context ownership, finalization, and isolation |
| `README.md`, `docs/guides/compilation.md` | Public examples and trace contract |

## Execution preparation

1. Use the execution workflow's worktree preparation before editing implementation files.
2. Incorporate merged PR #38, commit `81538e100a25be7a7d3ee9a66d9fd5a5433045ae`, while preserving approved design and plan commits.
3. Verify `Expression#explain` and its regression suite before beginning Task 1.
4. Record that integrated revision and preserve an isolated baseline checkout for final benchmark comparisons.

The planning checkout predates the merged inspection implementation.
Read its actual translator and signatures before sharing traversal helpers.
Do not implement a second public inspection contract.

### Task 1: Establish the private bounded collector

**Files:** Create the collector, its private signature, and `spec/unit/tracing_collector_spec.rb`. Modify `lib/jmespath.rb` and `sig/jmespath.rbs`.

**Interfaces:**

- `Tracing::Collector.new(root:, limit:)` maps syntax identity to inspection preorder IDs, including structural nodes.
- `operation_id(node) -> Integer` exposes this private map to traced evaluation.
- `within(node, index) { ... } -> value` pushes an iteration frame and restores context with ensure.
- `reference(node) { ... } -> value` assigns an invocation index, establishes its frame, and invokes the block.
- `emit(type, node, details = {}) -> void` snapshots the active context only while collection has capacity.
- `finish(value) -> trace_report` closes collection and returns the frozen report.
- `close -> void` closes collection on failure without returning a report.
- Define the public trace aliases listed in Task 2 now, so collector signatures validate independently.

- [x] **Step 1: Add failing collector tests.**

Assert a limit of 1 retains one event, with `truncated: false` until another diagnostic occurs.
Assert the second diagnostic sets truncation without increasing event count.
Assert `within` restores outer context after a raised exception.
Assert nested frames preserve order and copy their data before later context changes.
Assert event hashes, details, strings, frames, and arrays are frozen, while the returned value remains mutable.
Assert an event after `close` or `finish` cannot change a completed report.
Assert operation IDs agree with a separately obtained `explain`, including filter child order and structural entries.

- [x] **Step 2: Run `bundle exec rspec spec/unit/tracing_collector_spec.rb` and confirm missing-component failures.**
- [x] **Step 3: Implement the declared interfaces and their private RBS signatures.**

Use identity-based syntax lookup and the inspection translator's logical traversal order.
Load the collector through `lib/jmespath.rb`; leave the public trace method for Task 2.
Keep traversal, event storage, and counters local to the collector.
Use per-thread context stacks owned by the collector; remove completed stacks through ensure.
Protect event insertion, counter allocation, and finalization with a standard-library Mutex.
Hold no collector lock while invoking a user block or evaluating syntax.
Clear context storage and operation mappings when collection closes.

- [x] **Step 4: Run the collector tests and `bundle exec rake types`; require passing results.**
- [x] **Step 5: Commit only Task 1 files with `feat(tracing): add bounded diagnostic collection`.**

### Task 2: Expose traced evaluation and null-field diagnostics

**Files:** Create the traced evaluator and field lookup; modify expression loading and public signatures; add public and field-event tests.

**Interfaces:**

- `Tracing::Evaluator.new(functions:, disable_visit_errors: false, collector:)` reuses `Evaluator` handlers through inheritance.
- `Tracing::Evaluator#evaluate(node, data) -> value` intercepts fields and delegates remaining semantics.
- `Tracing::FieldLookup.call(data, name) -> [value, String?]` returns a reason only for a nil result.
- `Expression#trace(data, options = Options::EMPTY, limit: 1000, **keywords) -> trace_report` owns the collector lifetime.
- Public records: `trace_context = { operation_id: Integer, index: Integer }`, `trace_event`, and `trace_report`.
- `trace_event` fields: `type: String`, `operation_id: Integer`, `context: Array[trace_context]`, `details: Hash[Symbol, json]`.
- `trace_report` fields: `value: value`, `events: Array[trace_event]`, `truncated: bool`.

- [x] **Step 1: Add failing public and lookup tests.**

For `compile("x").trace({})`, assert the exact report with value nil, truncation false, and one event:

```ruby
{ type: "field_null", operation_id: 0, context: [],
  details: { name: "x", reason: "missing" } }
```

Assert `{x: nil}` and `{"x" => nil}` produce reason `null`.
Assert nil input produces `non_object`; `{"x" => nil, x: false}` returns false without events.
Assert false, zero, empty strings, selected objects, and mutable literal results match ordinary search.
Reject limits 0, -1, 1.0, nil, and true before reading an instrumented input stream.
Reject positional `:limit`, unknown options, conflicting options, and excessive nesting consistently with search.
Test saved registries and suppression defaults, per-call overrides, Pathname, StringIO, and ordinary Ruby inputs.
For R1, compare access logs from ordinary and traced searches using fresh Hash subclasses, default procs, and adapters.
Assert identical `[]`, `each_key`, `to_hash`, and `to_h` call counts and order where applicable.
Permit `unknown` for custom behavior, while pinning ordinary Hash reasons independently.
Assert no selected input or query result enters an event payload.

- [x] **Step 2: Run the new integration tests and confirm failures for the missing trace interface.**
- [x] **Step 3: Implement the declared interfaces and public YARD/RBS declarations.**

Use `Options.new` with the compiled expression's saved defaults and depth limit.
Load input exactly once and evaluate syntax through the dedicated evaluator.
Close collection in ensure, including input and evaluation failures.
Preserve the lookup sequence: string access, then symbol fallback only for nil.
Infer presence during the same lookup traversal; add no second conversion or application-observable lookup.
Keep ordinary `DataAccess.field`, field readers, and compiled plans unchanged.
Use inherited scalar, boolean, construction, slicing, and function handlers.

- [x] **Step 4: Run the three tracing test files and `bundle exec rake types`; require passing results.**
- [x] **Step 5: Commit only Task 2 files with `feat(expression): trace null field evaluation`.**

### Task 3: Explain filter exclusions and projection omissions

**Files:** Extend the traced evaluator and its private signatures; extend event and behavior integration tests.

**Interfaces:** Override `projection(node, data)`, `value_projection(node, data)`, and `filter_projection(node, data)` using Task 1 context and event methods.

- [x] **Step 1: Add failing omission and ordering tests.**

For `items[*].name` with `[{name: "Ada"}, {}, {name: false}]`, assert value `["Ada", false]`.
Assert the missing field event precedes a `projection_omission`, both carrying the projection's item index 1.
Assert omission details are empty and operation IDs match the field and projection nodes in `explain`.
For R2, instrument condition and projection functions; assert every condition runs before any projection callback.
Assert rejected filter indexes create gaps in the context of projected selected items.
Test nested filters and projections with exact outer-to-inner frame arrays.
Test value projections using ordinal indexes without enumerating object keys separately.
Test flattening, slices, and pipes to prove indexes refer to each immediate sequence.
Test short-circuit expressions with a failing callback in an unvisited branch; assert it remains uncalled and produces no diagnostic.
Test nil projection inputs, empty collections, nil filter conditions, and false projected values.
At limit 1, assert evaluation still completes all callbacks and returns the full ordinary result after truncation.

- [x] **Step 2: Run event and behavior tests; confirm missing diagnostic or context failures.**
- [x] **Step 3: Implement context-aware projections while retaining two-phase filters.**

Keep selected original indexes alongside selected values until projection completes.
Emit exclusions immediately after falsey conditions and omissions immediately after nil projected results.
Use the same array/object conversions and values sequence as ordinary evaluation.
Stop creating diagnostic snapshots after capacity is exceeded; continue normal evaluation.

- [x] **Step 4: Run all tracing tests plus `spec/unit/projections_spec.rb`; require passing results.**
- [x] **Step 5: Commit only Task 3 files with `feat(tracing): explain omitted projection items`.**

### Task 4: Preserve references, exception behavior, and concurrent isolation

**Files:** Extend the traced evaluator's reference handler; add concurrency tests and behavior regressions; adjust collector signatures if required.

**Interfaces:** Override `reference(node, data) -> ExpressionReference` and wrap requested evaluation with `collector.reference(node) { ... }`.

- [x] **Step 1: Add failing reference and lifecycle tests.**

Test `map`, `sort_by`, `min_by`, `max_by`, and a custom function invoking one reference repeatedly.
Assert reference frames use invocation counts, not inferred input positions, and preserve synchronous outer frames.
Assert deferred bodies are unvisited until called and execute exactly as often as ordinary evaluation.
For R3, save a reference through a callback; call it after success and failure, and assert ordinary results without completed-report changes.
Test a callback that starts another trace against the same expression; reports and counters remain independent.
For R5, start reference calls from two threads with barriers; assert separate contexts and exact total event limits.
Test eight concurrent top-level trace calls against one expression with distinct inputs and independent truncation states.
Assert callback bodies can overlap, proving collector locks do not serialize application execution.

- [x] **Step 2: Add parity tests for exceptions and suppression.**

For R4, raise a saved exception inside callbacks and converters, including library error classes and JSON parsing error classes.
Capture its backtrace at the application raise site; assert traced evaluation propagates the same object and backtrace.
Repeat with suppression enabled and with nested library validation failures inside callbacks.
Test genuine current-call validation suppression producing nil, including downstream projection omissions.
Compare fresh ordinary and traced inputs for callback order and conversion counts across optimized string functions and overridden built-ins.

- [x] **Step 3: Run the new regressions and confirm reference-context failures before implementation.**
- [x] **Step 4: Implement reference contexts and fix only parity defects established by failing tests.**

After collection closes, escaped references must evaluate without rebuilding mappings, contexts, counters, or events.
Preserve inherited function validation ownership and callback exception propagation.
Do not add a general rescue wrapper or attach reports to errors.

- [x] **Step 5: Run all tracing tests, `spec/integration/review_callbacks_spec.rb`, and `spec/integration/concurrency_spec.rb`; require passing results.**
- [x] **Step 6: Commit only Task 4 files with `fix(tracing): preserve reference and callback behavior`.**

### Task 5: Document and verify the complete public contract

**Files:** Update README and compilation guide; finish public YARD/RBS examples where tests identify gaps.

**Interfaces:** Document the Task 2 method and all approved event, context, reason, and limit rules without changing their schemas.

- [x] **Step 1: Add executable examples for a successful trace and bounded omission reporting.**

Document operation lookup through `explain`, local index semantics, reference invocation counts, and two-phase filter ordering.
State that report metadata is immutable while returned values retain ordinary mutability and identity.
Document conservative `unknown` reasons, error propagation, exact truncation behavior, and diagnostic memory limits.
Explain the absence of original-document paths, object keys, automatic logging, and a CLI trace flag.

- [x] **Step 2: Run `bundle exec rake` and `bundle exec rake docs`; require all required checks to pass.**
- [x] **Step 3: Compare ordinary search against the integrated pre-implementation baseline.**

Run `ruby script/benchmark.rb --ruby-root BASELINE_PATH --iterations 1000 --rounds 5 --memory --output REPORT_PATH` with concrete scratch paths.
Retain source/workload hashes, runtime settings, elapsed time, allocations, retained bytes, RSS, peak RSS, and startup measurements.
Assess search, cached, compiled, and churn modes separately; investigate repeatable ordinary-search regressions.
Use result-checked workloads and installed tools; request permission before installing any dependency.

- [x] **Step 4: Run `bundle exec rake package:check`, the repository prose checker, and `git diff --check`; require passing results.**
- [x] **Step 5: Review the complete diff against the approved design and preserve unrelated files.**
- [x] **Step 6: Commit documentation with `docs(tracing): document evaluation diagnostics` and report verified usage plus measured limitations.**

## Verification record

Implementation and review repairs are committed through `b5cb6e9`.
Local checks on MRI 4.0.9 passed: 6,170 examples, 100% line and branch coverage, lint, types, complexity, documentation, and packaging.
Independent QA found three parity defects; seven regression examples reproduced them before repair.
Focused independent QA passed after repair.

Benchmarks compare the integrated baseline `96cf93a` with the final implementation.
The full harness used 18 workloads, 1,000 iterations, five rounds, and memory measurements.
Four supplemental native string workloads used the same settings.
Reports retain source/workload hashes, runtime metadata, samples, allocations, retained bytes, RSS, and peak RSS outside the repository.

| Mode | Full harness time change | Native string workload time change |
| --- | --- | --- |
| Startup | +1.3% | +2.3% |
| Public search | +2.8% | -1.1% |
| Cached expression | -0.03% | -1.7% |
| Compiled expression | -0.8% | +0.7% |
| Compilation churn | +0.9% | +2.2% |

These are geometric means of per-workload median ratios, not universal speed guarantees.
Repeated searches add no allocations in either workload set.
Native string compilation adds one strategy array per compiled expression.
Loaded retained Ruby objects increased by approximately 6.5 KB; raw reports retain process-memory variation.
The largest public-search outlier reversed in a 100,000-iteration, seven-round repeat, so its initial slowdown was not repeatable.

The compiler retains selected native-function nodes without building trace events or logical operation IDs.
This preserves actual dispatch decisions without repeating registry callbacks.
Tracing preserves the initial field lookup predicate but uses core nil identity for additional diagnostic checks.
Struct conversions returning duck mappings receive conservative unknown classifications.

## Self-review

Tasks 1 and 2 establish bounded immutable diagnostics without modifying ordinary execution plans.
Task 3 covers each omission event and the approved local context rules.
Task 4 covers references, callbacks, exceptions, reentry, concurrency, and collector finalization.
Task 5 covers executable documentation, packaging, required quality checks, and ordinary-search measurements.
R1 through R5 have explicit tests in their owning tasks.
No task introduces a CLI mode, dependency, public parser object, or original-document path contract.
