# Required query results

Status: awaiting design approval. The user selected O1 and A1.
Scope: [issue #29](https://github.com/svyatov/jmespath-ruby/issues/29).

## Intent and boundaries

Add `Expression#fetch` for callers that require a non-null query result.
Preserve standard JMESPath semantics and the nullable behavior of `search` and `call`.
Exclude missing-versus-null detection, fallback values, block defaults, CLI changes, dependencies, and evaluation refactoring.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| A1: Call `search` once, then check for nil | Reuses input loading, option handling, and evaluation | Adds one public wrapper | Selected by the user |
| A2: Extract shared evaluation code | Gives both methods a common internal entry point | Changes evaluation code without a demonstrated need | Rejected |

The user selected O1: a dedicated error with an `expression` attribute.
O2, a dedicated error containing only a message, would require callers to retain or parse the query text.

## Public contract

Add `Expression#fetch(data, options = Options::EMPTY, **keywords)` with the same input forms and evaluation options as `search`.
Forward the input, positional options, and keyword options to `search` exactly once.
Return every non-nil result unchanged, including false, zero, empty strings, empty arrays, and empty hashes.
Preserve the identity and mutability of selected input objects.

When evaluation returns nil, raise `JMESPath::Errors::NullResultError < JMESPath::Errors::RuntimeError`.
Expose the compiled query text through the error's read-only `expression` attribute.
Use the message `Expression returned null`.
The error retains no input document or inferred explanation for the null result.

Missing fields, explicit null, out-of-range indexes, and suppressed validation failures producing nil receive the same error.
Saved suppression therefore converts a suppressed nil result into `NullResultError`.
A non-nil final result succeeds even if an intermediate operation returns nil.
Propagate all other evaluation, input, option, and application failures unchanged, including exception identity and backtrace.

## Implementation decisions

Keep the nil check within `fetch`; do not modify the evaluator, compiled plan, or suppression rules.
Use the frozen source string for the error's expression text.
The proposed error initializer accepts `expression:` and supplies the fixed message.
The initializer freezes an independent copy of supplied text, matching the syntax error convention.
These initializer details are builder proposals for approval with this design.

Update RBS with a non-null `Object` return type for `fetch` and the error's public constructor and attribute.
Add YARD documentation, a README example, and guidance in the compilation and errors guides.
CLI help remains unchanged because this feature adds no CLI interface.
Test placement and private implementation details remain builder decisions.

## Verification

Add focused failing regression tests before implementation.
Cover every null-producing case and each successful false, zero, or empty value.
Verify saved options, positional options, keyword overrides, custom functions, stream inputs, and selected object identity.
Verify one evaluation, unchanged application exception identity and backtrace, and unchanged `search` and `call` behavior.
Check the error hierarchy, fixed message, expression text, and source immutability.
Add executable documentation examples where applicable.
Preserve imported compliance fixtures.
Run `bundle exec rake` and `bundle exec rake docs`.
