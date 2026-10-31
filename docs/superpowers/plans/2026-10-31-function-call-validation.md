# Function call validation implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove validation-origin forwarding from built-in calculations while preserving observable function behavior.

**Architecture:** A private `Functions::FunctionCall` receiver executes one invocation within its validation scope. Scalar and collection calculations remain in focused modules. The receiver replaces the identity token allocated by `Functions#call`.

**Tech stack:** Ruby 3.3+, RSpec, RBS, Steep, and the repository's Rake checks.

**Spec:** [Approved project design](../specs/2026-10-31-jmespath-ruby-design.md), restricted to function execution. The user selected D1, the private receiver design, after comparing three alternatives.

## Global constraints

- Preserve the public `Functions#with`, `Functions#call`, `Functions.default`, and search interfaces.
- Preserve exception objects and backtraces from application callbacks and adapters.
- Preserve conversion order, conversion frequency, returned identity, and calculation algorithms.
- Keep evaluation state local to one call. Introduce no thread-local or global mutable state.
- Add no dependencies. Keep Ruby 3.3 support, 100% line and branch coverage, and the CRAP threshold of 10.
- Keep `sig/jmespath.rbs` unchanged unless verification exposes an incorrect public declaration.
- This plan authorizes local implementation only. Publication and remote delivery remain separate actions.

## Review focus

- R1: Nested searches can raise the same validation subclasses as the outer call. Preserve the nested exception.
- R2: Adapter conversion methods can reenter search. Preserve their exceptions, invocation order, and invocation count.
- R3: Concurrent searches can share a registry. Each invocation must retain its own validation scope.
- R4: Overrides must receive original values. Preserve registry immutability and callback argument identity.
- R5: Empty collections skip expression-key evaluation. Preserve stable sorting and selected-object identity.

## Problem

`Functions#call` allocates an identity token and supplies it to signature validation and built-in implementations.
Built-ins forward `origin:` through scalar calculations, collection calculations, coercions, and expression-key validation.
The callback-propagation fix, commit `8401538`, changed seven function files and three signature files.

This information leakage causes change amplification and cognitive load.
A calculation author must understand exception ownership to call a validation helper correctly.
The public registry interface already provides useful depth; the internal invocation seam needs better locality.

## Proposed interface

The public registry retains lookup and immutable registration.
After lookup, it delegates execution through this private interface:

```ruby
FunctionCall.new.call(
  definition, name, arguments,
  disable_visit_errors: disable_visit_errors
)
```

`Functions::FunctionCall#call(definition, name, arguments, disable_visit_errors: false)` returns a JMESPath value.
It validates the signature using `origin: self`, dispatches the implementation, and handles its own validation failures.
It suppresses `Signature::TypeMismatch` or `Signature::ArityMismatch` only when suppression is enabled and `error.origin.equal?(self)`.
All other failures propagate unchanged with bare `raise`.

Retain the validation exception subclasses and their origin readers.
Use the receiver as identity; allocate no second token.
Create a fresh receiver for every invocation, including custom callbacks.

`Definition` stores `signature` and `implementation`.
The implementation is either a trusted built-in handler symbol or a custom callback Proc.
Remove the redundant `builtin` field; dispatch by the implementation type.
Custom registration continues to store its supplied block.

The private registration interface becomes:

```ruby
with_builtin(name, signature:, handler:, variadic: false)
```

Keep scalar and collection registration methods on their modules.
They register trusted handler symbols, including `:contains?`, `:ends_with?`, and `:starts_with?`.
Query text must resolve through registered definitions before reaching handler dispatch.

Scalar and collection calculations become private instance methods included by `FunctionCall`.
They call shared coercion methods directly, such as `number(value)` and `array(value)`.
Remove `origin:` and unused keyword parameters from these calculations.

`Coercions` supplies instance methods and its standalone singleton methods through `extend self`.
Its private `validation_origin` returns `nil`; `FunctionCall` overrides it to return `self`.
Coercion failures use that origin without exposing an origin argument to callers.
Expression-key validation uses the same private method.
Preserve `Coercions.string(value)` for evaluator ordering and standalone coercion checks.
Keep calculation methods private without making standalone coercion methods inaccessible.

## Cohesion statement

**Single responsibility:** Execute one function call within its validation scope.

**Owns:** Signature validation, trusted handler dispatch, custom callback invocation, and suppression eligibility.

**Stays out:**

- Registry lookup and immutable registration remain in `Functions`.
- Calculation algorithms remain in Scalar and Collections.
- Ruby conversion protocols remain in DataAccess.
- Parsing, input loading, and expression evaluation retain their interfaces.
- Application callbacks retain responsibility for their own side effects.

## Dependency strategy

All affected dependencies are in-process.
Include the calculation and coercion modules behind the private invocation seam.
Add no adapter interfaces, dependency container, or ambient execution context.

Load `FunctionCall` after Scalar, Collections, and the reopened calculation modules are available.
Add its require in `lib/jmespath.rb` after the collection require.
Default registry construction records symbols without executing them, avoiding a require cycle.

## Testing strategy

Exercise behavior through `Functions#call` and `JMESPath.search`.
Retain the registry, signature, scalar, collection, callback, and compliance tests.
There are no direct calculation-helper tests to replace.
Keep the standalone coercion checks in `spec/unit/boundaries_spec.rb`.

Add only missing behavior coverage described in Task 1.
Characterization tests should pass before the refactor; do not manufacture failures by asserting private structure.
Use the same tests after the switchover.

## Migration strategy

Use one internal switchover after recording baseline behavior and performance.
The affected interfaces are private, so coexistence and public deprecation add no value.
Keep the behavior tests in a separate commit from implementation.
Preserve the approved project design and public documentation.

## Implementation steps

### Task 1: Record the behavior and performance baseline

**Files:** Modify `spec/integration/review_callbacks_spec.rb` and `spec/integration/concurrency_spec.rb`.
Use `spec/unit/functions_spec.rb` for any missing override-identity assertion.

**Interface:** Tests consume the public registry and search methods.

- [ ] Record the starting commit and working-tree state before editing.
- [ ] Extend the adapter reentry test to capture the raised object and its backtrace before propagating it.
- [ ] Assert that the outer search raises that identical object with the identical captured backtrace. This covers R1 and R2.
- [ ] Add a stateful string adapter whose first conversion returns a string and whose second conversion raises a captured exception.
- [ ] Assert that `length(@)` performs both conversions and propagates the second failure, including with suppression enabled. This covers R2.
- [ ] Add synchronized concurrent calls through one shared registry, mixing suppressible invalid inputs with nested callback failures.
- [ ] Assert separate results and exact nested exceptions without thread leaks or timing-based sleeps. This covers R3.
- [ ] Check an overridden built-in receives the original argument object and leaves its parent registry unchanged. Reuse existing coverage if sufficient.
- [ ] Retain the empty-key, stable-sort, and identity assertions in `spec/unit/collection_functions_spec.rb`. This covers R5.
- [ ] Run the focused command below. Expect all examples to pass before implementation.

```sh
bundle exec rspec spec/unit/functions_spec.rb spec/unit/signature_spec.rb spec/unit/scalar_functions_spec.rb spec/unit/collection_functions_spec.rb spec/unit/boundaries_spec.rb spec/integration/review_callbacks_spec.rb spec/integration/concurrency_spec.rb
```

- [ ] Capture baseline timings and allocations with a temporary standard-library Ruby script outside the repository.
- [ ] Measure direct scalar calls, `map` over 100 elements, `sort_by` over 100 elements, and a custom callback control.
- [ ] Check expected results outside timed sections. Use 1,000 warmups and five samples of 10,000 invocations per workload.
- [ ] Record Ruby version, JIT state, source commit, raw samples, and `GC.stat(:total_allocated_objects)` deltas.
- [ ] Commit the behavior tests with `test(functions): cover invocation isolation`.

### Task 2: Move execution into the private receiver

**Files:** Create `lib/jmespath/functions/function_call.rb` and `sig/internal/function_call.rbs`.
Modify `lib/jmespath.rb`, `lib/jmespath/functions.rb`, and the five calculation/coercion files below:

- `lib/jmespath/functions/coercions.rb`
- `lib/jmespath/functions/scalar.rb`
- `lib/jmespath/functions/conversion.rb`
- `lib/jmespath/functions/collections.rb`
- `lib/jmespath/functions/references.rb`

Modify `sig/internal/functions.rbs`, `sig/internal/scalar.rbs`, and `sig/internal/collections.rbs`.

**Interface:** Implement the Proposed interface section. Preserve `Signature#validate!` and the public registry interface.

- [ ] Add `Functions::FunctionCall` with its single execution entry point and private origin method.
- [ ] Change Definition and trusted built-in registration to store handler symbols or callback Procs.
- [ ] Convert calculation methods to private instance methods without changing their algorithms or conversion order.
- [ ] Make coercion methods usable through both the receiver and their standalone interface.
- [ ] Delegate `Functions#call` after lookup. Keep unknown-function failures outside suppression.
- [ ] Add load ordering and internal types for the receiver, implementation union, and instance methods.
- [ ] Remove obsolete `builtin`, `origin:` forwarding, registration closures, and unused keyword arguments.
- [ ] Run Task 1's focused command. Expect all examples to pass unchanged.
- [ ] Inspect the diff for unrelated algorithm changes and accidental public handler exposure.
- [ ] Commit with `refactor(functions): isolate function call validation`.

Estimated scope: eight library files, four internal signature files, and two or three test files.
Expect several hundred changed lines because singleton methods and type declarations change together.
Avoid splitting the switchover into temporarily incompatible interfaces.

### Task 3: Verify the completed switchover

**Files:** No additional production changes are expected. Keep measurement artifacts outside the repository.

- [ ] Run `bundle exec rake`. Expect all deterministic checks and full-suite coverage thresholds to pass.
- [ ] Run `bundle exec rake package:check`. Expect the installed-gem checks to pass with the new internal file packaged.
- [ ] Repeat baseline measurements in separate Ruby processes for the baseline and changed revisions.
- [ ] Alternate revision order across five pairs using the same interpreter, inputs, warmup, and iteration counts.
- [ ] Compare raw timing distributions and allocation deltas. Investigate a consistent slowdown or allocation increase before accepting the design.
- [ ] Do not claim performance neutrality from replacing one allocation alone. Report measured results and unresolved variance.
- [ ] Run the affected registry and nested-callback scenarios as QA, then request code review of the complete change.
- [ ] Confirm that calculations no longer forward validation identity and that the working tree contains only intended changes.
- [ ] Remove temporary scripts and temporary checkouts after retaining the result summary.

The implementation is complete when behavior, types, coverage, packaging, and the measured performance comparison support the switchover.
If the receiver fails to reduce internal interface complexity, report that result before expanding the design.
