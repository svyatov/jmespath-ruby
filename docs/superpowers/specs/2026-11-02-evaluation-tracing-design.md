# Evaluation tracing

Status: proposed for user approval.
Scope: [issue #16](https://github.com/svyatov/jmespath-ruby/issues/16).
Prerequisite: query inspection, merged in PR #38.

## Intent and scope

Explain field accesses returning nil, filter exclusions, and projection omissions during one evaluation.
Return the ordinary result together with bounded diagnostic events.
Preserve evaluation order, selected object identity, conversions, callbacks, exceptions, and suppression behavior.

The user selected a dedicated traced evaluator, approach A1.
The user accepted local item context without requiring paths back to the original document.
Concrete API names, event fields, limits, and context rules below are author proposals for approval.
This is a library feature with a public event contract and full design.

Exclude automatic logging, retries, query reruns, complete execution histories, input snapshots, and original-document provenance.
Exclude CLI tracing flags and changes to the interfaces planned in issues #17 through #30.
Preserve dependencies, imported fixtures, and ordinary search defaults.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| A1: Dedicated traced evaluator | Keeps ordinary search on its established execution path | Requires behavioral parity tests across evaluation paths | Selected by the user |
| A2: Instrument compiled execution plans | Traces optimized evaluation operations directly | Spreads instrumentation across builders and risks ordinary-search overhead | Not selected |

A1 reuses evaluator semantics and narrowly scoped helpers where practical.
Trace collection remains outside ordinary search and compilation.
Private decomposition must avoid copying the entire evaluator into a parallel implementation.

## Public interface

Add `Expression#trace(data, options = {}, limit: 1000, **keywords)` after `require "jmespath"`.
Accept the same input forms, positional evaluation options, keyword evaluation options, and configured defaults as `search`.
Reserve the keyword `limit` for tracing; reject positional `:limit` through ordinary option validation.
Require a positive Integer limit and raise ArgumentError before consuming input when the limit is invalid.
Add no module-level tracing method in this issue.

Return a frozen hash with exactly `:value`, `:events`, and `:truncated`.
`:value` is the ordinary evaluation result, including nil or false.
Preserve selected input object identity and ordinary mutability; never freeze or copy the returned value for tracing.
`:events` is a deeply frozen array of diagnostic hashes containing no input objects or computed query values.
`:truncated` is a boolean indicating that at least one diagnostic event was discarded.

For a compiled expression, this example describes the proposed interface:

```ruby
query = JMESPath.compile("items[*].name")
report = query.trace({items: [{name: "Ada"}, {}, {name: false}]})
report[:value] #=> ["Ada", false]
report[:truncated] #=> false
```

The report contains a null-field event and a projection-omission event for item index 1.
The false value produces neither event.
Operation IDs correspond to `query.explain`; IDs are local to the compiled query's explanation contract.

## Event contract

Each event has exactly `:type`, `:operation_id`, `:context`, and `:details`.
Keys use symbols; event types and detail enum values use strings.
`:operation_id` identifies the operation responsible for that diagnostic.
Resolve names and source ranges through `explain`; do not embed the complete explanation in every trace.

| Type | Operation | Details |
| --- | --- | --- |
| `field_null` | The field operation | `name: String`, `reason: String` |
| `filter_exclusion` | The filter_projection operation | Empty hash |
| `projection_omission` | The projection, value_projection, or filter_projection operation | Empty hash |

`field_null` occurs only when field access returns nil.
Its reason is `missing`, `null`, `non_object`, or `unknown`.
`missing` means the lookup established absence under the library's string-key and symbol-key fallback rules.
`null` means the lookup established an explicitly present nil under those rules.
`non_object` means the ordinary conversion path established that no object was available.
`unknown` means distinguishing absence from nil would require additional application-observable operations.

Preserve Hash defaults, custom lookup methods, conversion counts, and symbol fallback precedence.
Do not add conversions, callbacks, or observable lookups to refine a reason.
Conservative `unknown` classifications are acceptable for custom Hash behavior and adapters.
Define exact reason expectations for ordinary Hash inputs in regression tests.

A falsey filter condition produces one `filter_exclusion` event after its evaluation finishes.
A selected item's nil projected result produces one `projection_omission` event after evaluating the projected expression.
Emit field diagnostics before any resulting exclusion or omission.
Emit no events for successful fields, retained items, out-of-range indexes, or unvisited branches.
This contract explains the three requested causes; it does not explain every possible nil result.

## Local item context

`:context` is an ordered array of enclosing iteration frames, from outermost to innermost.
Each frame has exactly `:operation_id` and `:index`.
Indexes are zero-based positions in the immediate array or object-values sequence consumed by that operation.
Nested projections retain outer frames, so repeated operations can identify their local item unambiguously.
Events outside iteration have an empty context.

Filter condition frames use indexes from the filter's input array.
Projection frames for selected filter items retain those original indexes, including gaps caused by exclusions.
The exclusion or omission event includes the frame for the item being excluded or omitted.
Pipes and transformations establish local sequences; indexes do not claim positions in the original document.

Value projections use the ordinal position in the ordinary values sequence.
Do not enumerate keys separately to attach object keys.
Object keys are deferred because extra enumeration can change observable behavior for custom mappings.
This narrows the earlier suggestion of keys where available to one consistent index contract.

Expression references carry trace collection into evaluation requested by functions.
Add an expression-reference frame using that operation's ID and its zero-based invocation count within the trace call.
The invocation count is not an index into the function's input.
It allows repeated callback-driven evaluations to remain distinct without inferring function behavior.
Retain active enclosing frames when a reference is called synchronously during evaluation.
Stop collection when the top-level trace finishes or raises; later calls to escaped references must not mutate its report.
Normal reference evaluation remains available after collection stops.

## Evaluation and state

Build trace state per call, never on the shared frozen expression, default evaluator, or function registry.
Map private syntax nodes to the same logical operation IDs assigned by `explain`.
Reuse the inspection traversal contract, including filter child ordering, without exposing private nodes.
Only trace calls build or retain the operation mapping.

Keep filter evaluation in two phases: evaluate every condition, then project selected items.
Preserve left-to-right argument evaluation and boolean short-circuit behavior.
Evaluate expression references only when requested, preserving invocation order and counts.
Reuse function validation and suppression ownership, including nested callback behavior.

Do not rescue evaluation errors into a trace report.
Propagate the original exception with its identity and backtrace unchanged.
Do not attach traces to application exceptions or retry evaluation for diagnostics.
Suppressed validation failures retain their ordinary nil behavior and may cause downstream omissions.
This issue adds no dedicated validation-failure event.

Concurrent independent trace calls must have separate collectors, contexts, counters, and truncation state.
Nested trace calls from application callbacks must also remain independent.
Do not promise deterministic scheduling for custom functions that invoke references concurrently.
Protect collector finalization and the event limit if application code invokes references from concurrent threads.
Do not synchronize or reorder application callbacks to collect events.

## Limits and resources

Retain the first `limit` events in observed evaluation order.
Set `:truncated` only after a further diagnostic event occurs.
Exactly `limit` events without another diagnostic leave `:truncated` false.
Truncation emits no extra sentinel event and does not stop normal evaluation.
After truncation, avoid constructing further event snapshots.

Collection retains at most `limit` events and bounded context copies per retained event.
Operation mapping uses memory proportional to query size.
Do not retain input values, full documents, or intermediate results in diagnostics.
Filter bookkeeping may retain selected original indexes to preserve the documented two-phase order.
The event limit bounds diagnostics, not memory already required for evaluation or its bookkeeping.

## Verification and documentation

1. Add failing public-interface tests before implementing tracing.
2. Compare traced results with ordinary search, including selected object identity and result mutability.
3. Exercise fields, missing and explicit nil, defaults, symbol fallback, adapters, and custom lookup behavior.
4. Exercise false retention, nested filters, value projections, pipes, references, short circuits, and suppression.
5. Verify callback counts, conversion counts, evaluation order, exception identity, and exception backtraces.
6. Verify exact event order, matching inspection IDs, nested contexts, filter indexes, and reference invocation counts.
7. Verify invalid limits, exact limits, truncation, continued evaluation, and immutable diagnostics without freezing input.
8. Verify concurrent calls, nested calls, concurrent reference callbacks, and references invoked after report completion.
9. Measure ordinary-search overhead with the established benchmark harness before and after implementation.
10. Run `bundle exec rake` and `bundle exec rake docs` before claiming completion.

Use behavior-equivalent benchmark inputs and report source fingerprints, timing, and allocations.
Investigate a repeatable ordinary-search regression before accepting implementation.
Update the compilation guide, README example, public RBS, YARD, and executable documentation examples.
Keep CLI help accurate without adding an unspecified trace flag.
Verify packaged assets if implementation adds files outside paths included by the gemspec.

File names, helper boundaries, collector synchronization, and conservative lookup classification mechanics remain builder decisions.
Implement against merged query inspection before changing evaluation.
