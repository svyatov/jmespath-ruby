# Structured function validation errors

Status: approved by the user on 2026-11-01.
Scope: [issue #14](https://github.com/svyatov/jmespath-ruby/issues/14).

## Intent and scope

Let Ruby callers inspect function validation failures without parsing error messages.
Cover declared signatures, checks inside built-in functions, and invalid expression-reference results.
The user selected this scope as O1 and explicit context passing as A1.
This is a small change using the library's Ruby conventions and dependencies.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| A1: Pass context to validators | Identifies the owning invocation before an error is raised | Updates both execution paths and built-in validators | Selected by the user |
| A2: Enrich errors during rescue | Reduces context passed through calls | Requires additional checks to protect nested callback errors | Rejected |

## Public error data

Add read-only accessors to the public error classes.
Keep their ancestry, positional message constructors, and error messages compatible.
Manually constructed errors support absent metadata.
Metadata contains no argument values, expression-reference results, input documents, or callback objects.
Freeze metadata collections, including nested signature arrays.

Both `InvalidTypeError` and `InvalidArityError` expose:

| Accessor | Meaning |
| --- | --- |
| `function_name` | Function identifier, or nil without context |
| `signature` | Complete declared signature as an array of accepted-type arrays, or nil |
| `variadic?` | Whether the last declared argument repeats, or nil without context |
| `source_range` | Exclusive range of zero-based byte offsets for the failing function call, or nil |

`InvalidTypeError` also exposes:

| Accessor | Meaning |
| --- | --- |
| `argument_position` | One-based position in the actual argument list, or nil without context |
| `expected_types` | Accepted types at the failing check, or nil without context |
| `actual_type` | Rejected value's type symbol, including `:unknown`, or nil without context |
| `validation_stage` | `:argument` or `:expression_result`, or nil without context |

Use the type symbols accepted by `Functions#with`, including unions and homogeneous arrays.
For variadic arguments, report the actual argument position and the repeated trailing constraint.
For homogeneous-array failures, report the declared array constraint and actual outer type; omit element values and indices.

For `sort_by(items, &key)`, an invalid result identifies argument 2 and uses `:expression_result`.
Initially, accepted result types are `[:number, :string]`.
After the first valid result, the accepted type is that result's type, enforcing homogeneous keys.
The complete declared signature still identifies argument 2 as `[:expref]`.
For `min_by` and `max_by`, the expression reference is also argument 2.
Failures within a referenced function identify that inner function and retain its own source range.

`InvalidArityError` also exposes `expected_arity` and `actual_arity`, each an integer or nil without context.
`expected_arity` is the declared argument count; `variadic?` distinguishes an exact count from a minimum.

## Context and ownership

Pass immutable diagnostic context explicitly through compiled plans and the evaluator to the owning validators.
Include the optimized `length` and `reverse` fallback calls.
Use each function AST node's start and finish offsets for `source_range`.
Direct `Functions#call` failures expose signature data with a nil source range.
Keep diagnostic context private to evaluation; preserve the public `Functions#call` arguments.

Keep suppression origin separate from diagnostic context.
Preserve invocation-local origin checks and bare re-raising of ineligible failures.
Keep shared strict execution stateless; never store call context on a shared mutable receiver.
Preserve exception identity and backtrace for application callbacks, adapters, nested searches, and callbacks raising library error classes.
Never attach outer-call metadata to a callback exception.

Built-in conversion checks identify the owning function and argument using explicit context.
Reuse type observations from validation; do not repeat conversions to populate diagnostics.
Use `:unknown` when a more specific type would require another adapter conversion.
Preserve conversion order, conversion counts, argument evaluation order, and validation order.

## Constraints and non-goals

Keep query semantics, successful results, suppression eligibility, imported fixtures, and dependencies unchanged.
Do not retain values to support later inspection.
Do not add a formatter, CLI flag, JSON error mode, or automatic rendering of metadata.
Document the Ruby API and its absent-source behavior in the errors and functions guides.
Clarify validation behavior in CLI help without adding options or changing exit status and rendering.

## Verification and implementation decisions

Add focused regression tests before implementation.
Cover unions, typed arrays, empty arrays, variadic trailing arguments, and both arity boundaries.
Cover direct calls, nested calls, expression references, built-in conversion failures, compiled execution, and evaluator execution.
Assert source ranges against literal byte offsets, including queries containing multibyte characters.
Verify immutable metadata, absent context, callback identity, backtrace preservation, conversion counts, and suppression boundaries.
Update public RBS declarations and YARD documentation with executable examples.
Run `bundle exec rake` and `bundle exec rake docs`.
Verify packaged assets if implementation changes the packaged file set.

The user approved the accessor names, exclusive byte ranges, and the `:unknown` fallback with this design.
Private helper structure, context representation, and file organization remain implementation decisions.
