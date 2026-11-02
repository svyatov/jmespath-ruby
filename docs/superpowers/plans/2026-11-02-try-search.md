# Non-raising expression search implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Return library-owned failures from `Expression#try_search` while preserving application exceptions and successful null results.

**Architecture:** Use a private, fiber-local capture context per invocation. Record eligible errors by identity and suspend capture around application code. Return a frozen `SearchResult` that retains the original value or exception.

**Tech Stack:** Ruby 3.3+, RSpec, RBS, Steep, YARD, and installed development tools. No added dependencies.

**Spec:** [Approved design](../specs/2026-11-02-try-search-design.md).

## Global constraints

- Add `Expression#try_search` with the inputs and evaluation options accepted by `search`.
- The result container is frozen; it does not copy or freeze the value or error.
- Validate evaluation options before input access and error capture.
- Invalid options propagate as `ArgumentError`.
- Identify provenance during the original execution, without rerunning evaluation or conversions.
- Do not mutate exception objects to store ownership.
- Exclusion takes precedence over ownership.
- Threads and fibers do not share mutable capture records.
- Ordinary calls avoid allocating capture records.
- Preserve successful object identity and exception identity, metadata, and backtrace.
- Preserve imported compliance fixtures and dependency versions.
- A generic result framework, source compilation through `try_search`, and additional dependencies are outside scope.

## Review focus

- R1: A conversion raises `JSON::NestingError` inside `to_string`; its original exception must survive the built-in rescue handler. Task 2.
- R2: An overridden stream method raises an input error class; it must propagate while native stream errors become results. Task 3.
- R3: A callback re-raises an error obtained from an inner failure result; outer capture must preserve callback propagation. Task 4.
- R4: Two fibers alternate between library evaluation and suspended callbacks on the same thread; capture state must remain separate. Task 4.
- R5: A caller uses a frozen exception or an exception with custom equality; provenance must use identity without mutation. Task 4.

## File map

| File | Responsibility |
| --- | --- |
| `lib/jmespath/search_result.rb` | Public result readers and frozen container |
| `lib/jmespath/failure_capture.rb` | Private invocation context, identity records, and scope restoration |
| `lib/jmespath.rb` | Load result and capture definitions before their consumers |
| `lib/jmespath/expression.rb` | Public `try_search`, option validation, and owned depth failures |
| `lib/jmespath/functions.rb` | Owned unknown-function failures and excluded registry overrides |
| `lib/jmespath/functions/function_call.rb` | Excluded application callbacks |
| `lib/jmespath/functions/signature.rb` | Owned argument validation failures |
| `lib/jmespath/functions/coercions.rb` | Owned built-in coercion failures |
| `lib/jmespath/functions/references.rb` | Owned expression-result validation failures |
| `lib/jmespath/functions/conversion.rb` | Owned serialization failures and preserved application errors |
| `lib/jmespath/normalizer.rb` | Owned cycle failures |
| `lib/jmespath/data_access.rb` | Excluded application conversions |
| `lib/jmespath/input.rb` | Narrow native I/O and JSON capture with excluded application input methods |
| `sig/jmespath.rbs` | Public result readers and `try_search` types |
| `sig/internal/failure_capture.rbs` | Private result construction and capture types |
| `sig/internal/api.rbs`, `sig/internal/values.rbs` | Changed private expression, input, and conversion helper types |
| `spec/integration/try_search_spec.rb` | Values, options, evaluation ownership, and application exceptions |
| `spec/integration/try_search_input_spec.rb` | Native input failures, application overrides, and resource lifetime |
| `spec/integration/try_search_context_spec.rb` | Nesting, reuse, threads, fibers, and restoration |
| `docs/guides/search.md`, `docs/guides/errors.md`, `docs/guides/compilation.md` | Public behavior and executable examples |

### Task 1: Return immutable successful results

**Interfaces:**

- Add `Expression#try_search(data, options = Options::EMPTY, **keywords) -> SearchResult`.
- Add `SearchResult#success?() -> bool`, `#value() -> value`, and `#error() -> StandardError?`.
- Use internal `SearchResult#initialize(value:, error:)`, marked `@api private`; failure construction always supplies a nil value.
- Add private `FailureCapture.run { value } -> SearchResult`, `FailureCapture.owned(error) -> error`, and `FailureCapture.application { value } -> value`.
- Add private `FailureCapture.excluded?(error) -> bool` for rescue handlers that could replace application exceptions.

- [x] **Step 1: Write success and option regressions in `spec/integration/try_search_spec.rb`.**

Include named examples with these assertions:

```ruby
it "distinguishes successful null and false" do
  [nil, false].each do |value|
    result = JMESPath.compile("@").try_search(value)
    expect(result).to be_a(JMESPath::SearchResult)
    expect(result).to be_frozen
    expect(result.success?).to be(true)
    expect(result.value).to equal(value)
    expect(result.error).to be_nil
  end
end

it "preserves mutable value identity" do
  value = { "items" => [] }
  result = JMESPath.compile("@").try_search(value)
  expect(result.value).to equal(value)
  expect(value).not_to be_frozen
  expect(value.fetch("items")).not_to be_frozen
end
```

Add a numeric success case and compare positional and keyword options with ordinary `search`.
For unknown options, conflicting options, invalid booleans, invalid registries, invalid depth, and non-Hash positional options, assert `ArgumentError` before input access.
Use a `StringIO` whose `read` raises if invoked to prove validation order.

- [x] **Step 2: Run the regressions before implementation.**

Run `bundle exec rspec spec/integration/try_search_spec.rb`.
Expect failures for missing `try_search`, not invalid test setup.

- [x] **Step 3: Implement result construction, scoped capture, and successful evaluation.**

Create the two library files and their require entries.
Store contexts with `Thread.current[key]`, which is fiber-local; use identity hashes for owned and excluded exceptions.
`run` installs a fresh context and restores the previous context in `ensure`.
Rescue only eligible library, JSON parser, I/O, and operating-system classes when creating failure results.
Return a failure only for an owned, non-excluded exception; otherwise re-raise.
`owned(error)` records the error in the active context and returns the identical object; without a context, return it without allocation.
`application` suspends the active context, records escaping application exceptions on the saved context, and restores it in `ensure`.
Bookkeeping may rescue `StandardError` only to record and re-raise; it must never turn an arbitrary application exception into a result.
With no active context, `application` yields directly.
Validate options once before `run`; preserve the no-option compiled plan and configured evaluator selection used by `search`.
Avoid calling `search` with reconstructed options that would change the selected path or repeat validation.
Keep `search`, `call`, `fetch`, and `trace` behavior unchanged.
Add public types and private helper signatures with implementation.

- [x] **Step 4: Verify the public value contract and commit.**

Run `bundle exec rspec spec/integration/try_search_spec.rb spec/integration/configured_queries_spec.rb spec/integration/required_result_spec.rb`.
Run `bundle exec rake types`; expect all examples and type checks to pass.
Commit only Task 1 files with `feat(search): add immutable try_search results`.

### Task 2: Capture evaluation failures and preserve application exceptions

**Interfaces:** Consume the result readers and private capture helpers from Task 1. Preserve all function and conversion signatures.

- [x] **Step 1: Add evaluation and application-provenance regressions.**

Use a configured expression for the compiled path and a different per-call registry for the evaluator path.
Test `length(@)` on `4`, `length()`, `missing()`, cyclic normalization through `to_string(@)`, and rejected `sort_by` expression results.
Assert failure status, nil value, the expected error class, and preserved structured function metadata.
Test a compiled `a.b` with per-call `max_depth: 1`; assert a failure containing `Errors::SyntaxError`.
Assert `disable_visit_errors: true` returns successful null for type and arity failures but still captures unknown-function errors.
Check suppression both as a configured default and as a per-call override.

For each callback and `to_str`, `to_ary`, and `to_hash` conversion, raise a saved exception instance.
Cover `Errors::InvalidTypeError`, `Errors::InvalidArityError`, `Errors::UnknownFunctionError`, `Errors::InvalidValueError`, `JSON::ParserError`, `JSON::NestingError`, and an unrelated application error.
Assert the raised object and its backtrace are unchanged, including under suppression and nested function references.
For R1, raise the saved nesting error from a conversion reached by `to_string(@)` and assert it propagates unchanged.
Compare stateful conversion call counts and order against ordinary `search`; do not add a second conversion for ownership checks.
Test a registry subclass overriding `call`, including its compiled keyword omission and evaluator's explicit false.
Assert callback and registry overrides execute once, with the same argument order as `search`.

- [x] **Step 2: Run evaluation regressions before ownership changes.**

Run `bundle exec rspec spec/integration/try_search_spec.rb`.
Expect library-failure assertions to fail because those errors are not yet recorded as owned.

- [x] **Step 3: Instrument actual evaluation failure sites and application calls.**

Use `raise FailureCapture.owned(error)` at the actual library raise sites listed in the file map.
Record failures where signature checks, coercions, expression-result checks, unknown lookup, cycle detection, and expression depth reject evaluation.
Do not mark error constructors globally; applications may construct the same public error classes.
Leave parser failures outside the compiled interface and do not modify source compilation.
Wrap custom function implementation calls and overridden registry dispatch in `FailureCapture.application`.
Wrap conversion protocol invocation, including overridden `Struct#to_h` and custom conversion discovery, without changing conversion order or counts.
In the serialization nesting rescue, re-raise an excluded application error before constructing an owned `InvalidValueError`.
Preserve `FunctionCall` origin-based suppression; do not replace it with capture ownership.
Verify optimized `length` and `reverse` fallbacks still enter instrumented validation.
Update private RBS only for helpers whose signatures change.

- [x] **Step 4: Verify evaluation compatibility and commit.**

Run `bundle exec rspec spec/integration/try_search_spec.rb spec/integration/review_callbacks_spec.rb spec/integration/function_validation_context_spec.rb spec/integration/review_cycles_spec.rb spec/unit/data_access_spec.rb`.
Run `bundle exec rake types`; expect passing examples and types.
Commit only Task 2 files with `feat(search): capture owned evaluation failures`.

### Task 3: Capture native input failures

**Interfaces:** Preserve `Input.load(data) -> value`; use Task 1 capture helpers only around eligible native operations and parser calls.

- [x] **Step 1: Write input ownership and resource regressions in `spec/integration/try_search_input_spec.rb`.**

Assert malformed JSON from `StringIO`, an open file, and `Pathname` produces failure results containing `JSON::ParserError`.
Assert a missing `Pathname` produces `Errno::ENOENT` and closed native `IO` and `StringIO` produce `IOError` failure results.
Compare captured exception identity and backtrace with the exception observed at the failing native operation; never perform a second read.
Assert streams read from their original positions and caller-owned streams remain open after success, parsing failure, and evaluation failure.
Assert library-opened files close after success and each failure.
Inject an owned-file read failure and assert cleanup still runs without replacing its exception.
For R2, override `read` on an IO or StringIO subclass to raise saved JSON, library, I/O, and system-call exceptions.
Assert those exceptions propagate unchanged and `read` runs once.
Test overridden `Pathname#to_path`, stream result `to_s`, and nested queries inside those methods as application conversions.
Assert a plain string remains an ordinary Ruby input value rather than being parsed as JSON.

- [x] **Step 2: Run input regressions before implementation.**

Run `bundle exec rspec spec/integration/try_search_input_spec.rb`.
Expect native input failure assertions to fail because input errors are not yet recorded as owned.

- [x] **Step 3: Add narrow native-operation ownership in `lib/jmespath/input.rb`.**

Separate path conversion, stream reading, stream result conversion, and JSON parsing sufficiently to identify their error origins.
Treat application method overrides as excluded calls while retaining native method dispatch and existing inputs.
Use native method ownership to distinguish overrides without invoking conversions during inspection.
Record native open, read, and close failures only where those operations occur; preserve file block cleanup.
Record JSON parser failures only around the library's parser invocation.
Protect application conversion errors from enclosing I/O and parser rescues with the exclusion check.
Avoid new rescue behavior or capture allocations when no context is active.
Update `sig/internal/api.rbs` for any private input helpers.

- [x] **Step 4: Verify input compatibility and commit.**

Run `bundle exec rspec spec/integration/try_search_input_spec.rb spec/integration/try_search_spec.rb spec/integration/search_spec.rb spec/integration/cli_file_spec.rb spec/integration/cli_json_lines_spec.rb`.
Run `bundle exec rake types`; expect passing examples and types.
Commit only Task 3 files with `feat(search): capture native input failures`.

### Task 4: Verify context isolation and document the interface

**Interfaces:** Consume the complete `Expression#try_search` contract from Tasks 1 through 3. Add no public methods.

- [x] **Step 1: Add context regressions in `spec/integration/try_search_context_spec.rb`.**

Test a callback that invokes failing ordinary `JMESPath.search`; assert the outer `try_search` propagates the inner exception unchanged.
Test a callback that handles an inner `try_search` failure and returns a value; assert outer success.
For R3, re-raise the inner result's error from that callback; assert outer propagation of that exact object.
Repeat nested searches from conversions, registry overrides, and function references.
After a callback or conversion returns normally, trigger an outer library failure and assert capture resumes correctly.
After each success or exception, perform an ordinary failing `search` and a fresh `try_search`; assert their expected independent behavior.
Use queues to interleave threads sharing one compiled expression, with one callback failure and one library failure.
For R4, alternate two fibers with explicit `Fiber.yield` inside callbacks and verify isolated results and restored outer scopes.
Assert new threads and fibers do not inherit a parent's active capture context.
For R5, raise an exception frozen with an explicit backtrace; observe the actual escaping object in an application rescue before re-raising.
Ruby can copy frozen exceptions during `raise`; compare against that observed object and confirm the original remains frozen and unchanged.
Use distinct exceptions overriding `==`, `eql?`, and `hash`; assert identity-based exclusion and no stale records across calls.
Re-raise a prior failure result's error inside application code in a later call; assert propagation.
Verify a callback that rescues an application failure can return normally, allowing a later owned failure to be captured.

- [x] **Step 2: Run context regressions and resolve contract failures.**

Run `bundle exec rspec spec/integration/try_search_context_spec.rb spec/integration/try_search_spec.rb spec/integration/try_search_input_spec.rb`.
Expect all examples to pass; fix any provenance or restoration failure before documentation.
Keep fixes within A1 and the approved public contract.

- [x] **Step 3: Document results, ownership, and nested calls.**

Add YARD for `try_search` and all public result readers, including successful null, false, and failure examples.
Update the search, error, and compilation guides with executable examples showing `success?`, `value`, and `error`.
Explain that values and errors retain identity and remain independently mutable.
State the native input policy, callback propagation rule, suppressed-null behavior, and invalid-option propagation.
Show an inner `try_search` handled inside a callback without implying that outer capture swallows callback exceptions.
Review CLI help; the Ruby-only method needs no new flag, result mode, or unrelated help edit.

- [x] **Step 4: Run complete verification and exercise the public interface.**

Run `env RUBOCOP_CACHE_ROOT=/private/tmp/jmespath-rubocop-cache bundle exec rake`.
Require passing lint, RBS, Steep, RSpec, 100% line and branch coverage, complexity analysis, and executable documentation checks.
Run `bundle exec rake docs`; require successful YARD generation without warnings.
Run `bundle exec ruby -Ilib -rjmespath -e 'r = JMESPath.compile("length(@)").try_search(4); p [r.success?, r.value, r.error.class, r.frozen?]'`.
Expect `[false, nil, JMESPath::Functions::Signature::TypeMismatch, true]`, retaining the library's original validation subclass.
Run the repository prose checker on touched documentation and `git diff --check`.
Review the diff for unrelated edits, imported fixture changes, dependencies, and capture state on shared objects.
Run `bundle exec rake package:check`; require a valid isolated gem and successful packaged examples.
Confirm the gem includes both additional runtime files through the gemspec's `lib/**/*.rb` pattern.

- [x] **Step 5: Commit context coverage and documentation.**

Commit only Task 4 files with `feat(search): document try_search failure ownership`.
Record actual verification results without claiming CI or publication evidence.
Remote publication and pull request creation require separate authorization.

## Verification record

Implemented on `feat/try-search` in `/private/tmp/jmespath-try-search`.
Result, evaluation, input, and provenance regressions failed before their respective implementation changes.
Private capture helpers moved from Task 1 to Task 2 to accompany their first consumers.
The depth-limit regression uses `length(a.b)` because `a.b` remains valid at depth 1.
Exploratory checks added excluded Hash lookup callbacks, JSON serialization hooks, and ordinary public evaluation entry points.
Native stream inspection bypasses application reflection overrides and identifies Ruby replacements of native read methods.
Each ownership correction has a regression observed failing before the fix.

`bundle exec rake` passes 6,610 examples with 100% line and branch coverage, lint, RBS, Steep, complexity analysis, and executable documentation.
`bundle exec rake docs` and `bundle exec rake package:check` pass.
The artifact includes the result, capture, and serializer helper files.
Public API QA passes on Ruby 4.0.9 and Ruby 3.3.11, both using JSON 3.1.0.
The corrected public flows also pass on Ruby 3.3.11 with JSON 2.7.2.
Ruby 4.0 emits the installed YARD dependency's `irb/notifier` default-gem warning; YARD reports no documentation failures.
The prose checker and `git diff --check` pass.

A fresh reviewer identified serialization provenance, native path coercion, and fallback output defects.
All three received failing regressions before correction; no findings were deferred.
The output-changing finding was regraded from Minor to Important and fixed in the same pass.
Guarded Hash keys preserve key conversion and serialization order.
The native generation rescue excludes normalization failures while ordinary search retains its compatibility behavior.
`File.path` preserves chained path coercion; native string generation preserves JSON fallback without an extra serializer callback.
The correction pass passed the complete gate, documentation generation, package verification, and public API QA.
