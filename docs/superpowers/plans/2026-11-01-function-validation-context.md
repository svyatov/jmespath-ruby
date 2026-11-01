# Structured function validation errors implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Expose structured function validation errors while preserving evaluation behavior and application exceptions.

**Architecture:** Pass immutable context from execution paths to validators, including checks inside built-ins. Keep suppression origin independent of diagnostic context. Preserve public registry dispatch and stateless shared execution.

**Tech Stack:** Ruby 3.3+, RSpec, RBS, Steep, YARD, and the locked development bundle.

**Spec:** [Approved design](../specs/2026-11-01-function-validation-context-design.md).

**Status:** Implemented and verified on 2026-11-02.

## Global constraints

- Keep their ancestry, positional message constructors, and error messages compatible.
- Metadata contains no argument values, expression-reference results, input documents, or callback objects.
- Freeze metadata collections, including nested signature arrays.
- Keep diagnostic context private to evaluation; preserve the public `Functions#call` arguments.
- Keep shared strict execution stateless; never store call context on a shared mutable receiver.
- Preserve conversion order, conversion counts, argument evaluation order, and validation order.
- Keep query semantics, successful results, suppression eligibility, imported fixtures, and dependencies unchanged.
- Do not add a formatter, CLI flag, JSON error mode, or automatic rendering of metadata.

## Review focus

- R1: A registry subclass with an exact `call` signature still receives compiled and evaluator dispatch.
- R2: A stateful adapter fails during a later conversion without additional diagnostic conversions.
- R3: A callback's nested query error retains its inner function, range, identity, and backtrace.
- R4: Concurrent searches sharing compiled operations never exchange diagnostic context or suppression origins.
- R5: Successful optimized string operations retain their direct path; fallback failures expose the correct range.

## File map

| Files | Responsibility |
| --- | --- |
| `lib/jmespath/errors.rb`, `sig/jmespath.rbs` | Public error accessors and compatible constructors |
| `lib/jmespath/functions/validation_context.rb`, `sig/internal/validation_context.rbs` | Private immutable context and error construction |
| `lib/jmespath/functions.rb`, `functions/signature.rb`, `functions/function_call.rb` | Registry entry points, signature checks, and invocation ownership |
| `lib/jmespath/functions/{scalar,collections,references,coercions,conversion}.rb` | Context at built-in checks |
| `lib/jmespath/{plan.rb,evaluation/scalars.rb}` | Source ranges from AST nodes |
| `sig/internal/{functions,function_call,scalar,collections,plan}.rbs` | Types for modified internal interfaces |
| `spec/unit/function_validation_context_spec.rb` | Direct-call metadata and built-in checks |
| `spec/integration/function_validation_context_spec.rb` | Execution paths, locations, and isolation |
| `spec/integration/{review_callbacks,concurrency,configured_queries,cli}_spec.rb` | Compatibility and CLI regression coverage |
| `docs/guides/{errors,functions}.md`, `lib/jmespath/cli.rb` | Public examples and CLI help |

Require the context helper from `functions.rb` after `functions/signature`.
The gemspec includes `lib/**/*.rb`; preserve that inclusion and verify the packaged helper.
Preserve the unrelated untracked `oss-audit-report.md`.

### Task 1: Expose signature diagnostics for direct calls

**Files:** Modify the public errors, registry, signature validator, invocation dispatcher, and corresponding RBS files from the map. Create the context helper and unit spec.

**Interfaces:**
- Public error accessors follow the design's exact names and nullable types.
- Private `ValidationContext.new(name, signature, source_range: nil)` takes `String`, `Signature`, and optional `Range[Integer]`.
- `ValidationContext#type_error(message, position:, expected_types:, actual_type:, origin:, stage: :argument)` returns `Signature::TypeMismatch`.
- `ValidationContext#arity_error(message, actual_arity:, origin:)` returns `Signature::ArityMismatch`.
- `Signature#validate!(values, name, origin: nil, context: nil)` preserves direct internal calls while accepting diagnostic context.
- `FunctionCall#call(definition, name, arguments, disable_visit_errors: false, context: nil)` keeps the strict receiver stateless.
- `Functions#call(name, arguments, disable_visit_errors: false)` keeps its public signature.

- [x] **Step 1: Add unit regressions for public metadata.**

For `Functions.default.call("join", [",", [1, 2]])`, assert:

```ruby
expect(error.function_name).to eq("join")
expect(error.signature).to eq([[:string], [:array_string]])
expect(error.variadic?).to be(false)
expect(error.argument_position).to eq(2)
expect(error.expected_types).to eq([:array_string])
expect(error.actual_type).to eq(:array)
expect(error.validation_stage).to eq(:argument)
expect(error.source_range).to be_nil
expect(error.message).to eq("Invalid argument 2 for join: array")
```

Use separate examples for `length(nil)`'s full union and `sort([1, "x"])`'s typed-array union.
Assert empty arrays succeed for `join` and `sort`.
For `merge({}, {}, 3)`, assert position 3, signature `[[:object]]`, expected types `[:object]`, and `variadic? == true`.
For `length()` and `length(1, 2)`, assert expected arity 1 and actual arity 0 and 2, respectively.
For `merge()`, assert expected arity 1, actual arity 0, and `variadic? == true`.
For a zero-argument custom function receiving one argument, assert expected arity 0 and actual arity 1.
Assert the positional constructors preserve their messages and return nil for each metadata accessor.
Assert metadata strings, arrays, nested signature arrays, and any supplied ranges are immutable independent snapshots.

- [x] **Step 2: Run the regressions before implementation.**

Run `bundle exec rspec spec/unit/function_validation_context_spec.rb`.
Expected: failures for missing metadata accessors.

- [x] **Step 3: Implement the public accessors and private context interfaces.**

Keep origin matching in `FunctionCall#call` and preserve bare `raise` for ineligible errors.
Pass context to signature checks without storing it on `FunctionCall::STRICT`.
Expose immutable declared arguments and variadic state from `Signature` through private implementation APIs.
Retain the existing matching and actual-type conversion sequence; populate metadata from those observations.
Keep direct calls to coercion singleton helpers valid without context.
Update RBS and YARD alongside each interface.

- [x] **Step 4: Verify direct calls and suppression compatibility.**

Run `bundle exec rspec spec/unit/function_validation_context_spec.rb spec/unit/signature_spec.rb spec/unit/functions_spec.rb spec/integration/review_callbacks_spec.rb`.
Expected: all examples pass, including existing origin and backtrace assertions.

- [x] **Step 5: Commit only Task 1 files.**

Use `feat(errors): expose structured signature validation data`.

### Task 2: Add context to built-in validation

**Files:** Modify `function_call.rb`, the five built-in files in the map, their RBS declarations, and the unit context spec. Extend `review_callbacks_spec.rb`.

**Interfaces:** Built-in handlers accept an internal `context:` keyword; custom callbacks receive only their original positional arguments.
Coercion helpers accept optional `context:` and `position:` keywords and continue to accept their original single argument.
`checked_type(value, expected, context:)` reports argument 2 with stage `:expression_result`.
Use Task 1's context error factories and preserve `validation_origin` independently.

- [x] **Step 1: Add regressions for result constraints and later conversion failures.**

For each of `sort_by`, `min_by`, and `max_by`, test keys `[false]`, `[1, "x"]`, and `["x", 1]`.
Assert argument 2, stage `:expression_result`, actual types `:boolean`, `:string`, and `:number`, respectively.
Assert expected types `[:number, :string]`, `[:number]`, and `[:string]`, respectively.
Assert the signature remains `[[:array], [:expref]]`.
For empty inputs, assert references are never evaluated and successful results remain unchanged.
For `contains("abc", 4)`, assert argument 2, expected `[:string]`, actual `:number`, and stage `:argument`.
For R2, use a string adapter whose first conversion returns `"abc"` and whose second returns nil.
Assert exactly two `to_str` calls and an `:unknown` actual type when further classification would require conversion.
Retain the existing adapter test whose second conversion raises an application exception; assert its identity and unchanged backtrace.
For both library error classes, have custom callbacks raise manually constructed errors and errors from nested searches.
Assert suppression preserves these callback errors and does not attach outer metadata.

- [x] **Step 2: Run the added regressions before implementation.**

Run `bundle exec rspec spec/unit/function_validation_context_spec.rb spec/integration/review_callbacks_spec.rb`.
Expected: failures for absent built-in metadata; callback compatibility assertions continue to pass.

- [x] **Step 3: Thread context through handlers and coercion checks.**

Pass the correct argument position explicitly, including each actual variadic position in `merge`.
Preserve helper call order within `join`, `contains?`, `length`, and `avg`.
Reuse `checked_type`'s observed type when reporting invalid or inconsistent expression keys.
At coercion failures, classify native primitives directly; use `:unknown` when adapter classification requires another conversion.
Preserve singleton coercion errors without context and avoid retaining values in metadata.
Update every changed built-in signature in RBS, including conversion handlers accepting unused context.

- [x] **Step 4: Verify built-ins and exception boundaries.**

Run `bundle exec rspec spec/unit/function_validation_context_spec.rb spec/unit/scalar_functions_spec.rb spec/unit/collection_functions_spec.rb spec/unit/boundaries_spec.rb spec/integration/review_callbacks_spec.rb`.
Expected: all examples pass with unchanged conversion counts and successful results.

- [x] **Step 5: Commit only Task 2 files.**

Use `feat(errors): describe built-in validation failures`.

### Task 3: Preserve source ranges across execution paths

**Files:** Modify `functions.rb`, `plan.rb`, `evaluation/scalars.rb`, and corresponding RBS declarations. Create the integration context spec. Extend configured-query and concurrency specs.

**Interfaces:** Add `Functions#call_with_context(name, arguments, source_range:, disable_visit_errors: false)` as `@api private`.
This entry builds Task 1's context and shares dispatch logic with the public call.
For registry subclasses overriding `call`, delegate to their original `call` contract without extra keywords.
Do not enrich errors from that delegated application code.
Change `Plan::Builder#function_call` and `#string_function` to accept the function AST node or its source range explicitly.
The evaluator supplies `(node.start...node.finish)` for each function invocation.

- [x] **Step 1: Add source-range and execution-boundary regressions.**

Run equivalent assertions through a configured compiled plan and a search-time registry override forcing evaluator execution.
Assert `length(reverse(@))` on numeric input identifies `reverse`, range `7...17`, and argument 1.
Assert `map(&length(@), @)` on `[4]` identifies `length` and range `5...14`.
Assert `'é' | length(@)` with `length` overridden to accept numbers identifies range `7...16`, using byte offsets.
For R5, test `length(@)` and `reverse(@)` on invalid numbers and valid native strings.
Assert optimized fallback failures identify ranges `0...9` and `0...10`, respectively.
For R1, define a subclass with `call(name, arguments, disable_visit_errors: false)` that returns 42.
Assert compiled and evaluator calls return 42 without extra keyword errors.
For R3, have a custom callback raise a captured error from `JMESPath.search("reverse(@)", 4)`.
Assert the error retains `reverse`, `0...10`, its identity, and its captured backtrace across outer calls.
For R4, use synchronized concurrent searches of two compiled expressions sharing one registry.
Assert each error retains its own function, range, signature, and suppression behavior.
Assert suppressed inner reference failures still yield the established successful outer results, such as `[nil]` from `map`.

- [x] **Step 2: Run the integration regressions before implementation.**

Run `bundle exec rspec spec/integration/function_validation_context_spec.rb spec/integration/configured_queries_spec.rb spec/integration/concurrency_spec.rb`.
Expected: source-range assertions fail while established dispatch behavior remains covered.

- [x] **Step 3: Pass AST ranges through all library execution paths.**

Route native registry calls through the contextual entry while preserving subclass dispatch.
Keep optimized successful string calls direct; send their fallback failures through contextual validation.
Preserve unknown-function timing after argument evaluation.
Create immutable context per call or reuse immutable compiled context; never mutate shared evaluators or registries.
Do not catch callback errors to attach ranges.

- [x] **Step 4: Verify both execution paths and concurrency.**

Run `bundle exec rspec spec/integration/function_validation_context_spec.rb spec/integration/configured_queries_spec.rb spec/integration/concurrency_spec.rb spec/integration/review_callbacks_spec.rb spec/unit/evaluator_spec.rb`.
Expected: all examples pass, including R1 through R5.

- [x] **Step 5: Commit only Task 3 files.**

Use `feat(errors): attach function source ranges`.

### Task 4: Document the API and verify the complete change

**Files:** Modify `docs/guides/errors.md`, `docs/guides/functions.md`, `lib/jmespath/cli.rb`, and `spec/integration/cli_spec.rb`. Complete public YARD and RBS declarations in the files already changed.

**Interfaces:** CLI help explains function validation; error rendering, executable names, options, and exit statuses retain their contracts.

- [x] **Step 1: Add a failing help regression.**

Assert `--help` describes function validation and succeeds without reading JSON.
Assert an invalid `length(@)` invocation still returns status 1, empty stdout, and the original message on stderr.
Assert usage failures still return status 2.

- [x] **Step 2: Run CLI regressions before the help change.**

Run `bundle exec rspec spec/integration/cli_spec.rb`.
Expected: the validation-help assertion fails.

- [x] **Step 3: Document metadata and clarify help.**

Document all accessors, nullable metadata, array unions, variadic arity, expression-result constraints, and exclusive byte ranges.
Add executable Ruby examples inspecting rescued errors from query evaluation and direct `Functions#call`.
Explain that complete signatures and failure-specific constraints serve different purposes.
Explain the `:unknown` fallback and preserve all suppression guarantees.
Add this help sentence: `Function arguments and expression-reference results are validated; failures exit with status 1.`
Keep help text separate from the usage string used for invalid command invocations.

- [x] **Step 4: Run required checks and package verification.**

Run `bundle exec rake` and require success, including coverage, CRAP, RuboCop, RBS, Steep, and executable documentation.
Run `bundle exec rake docs` and require success without YARD warnings.
Run `bundle exec rake package:check` and require the installed gem smoke checks to pass.
Run the oss-writing prose checker with Bun on the two modified guides.
Run `git diff --check` and require success.
Inspect the final diff for imported-fixture changes, extra dependencies, retained argument values, and unrelated edits.
Only broaden testing when failures or further changes justify it.

- [x] **Step 5: Commit the documentation and report verified behavior.**

Use `docs(errors): explain function validation metadata`.
Report the public Ruby inspection example, the checks actually run, and any remaining limitation.
Keep publication and remote operations outside this plan.
