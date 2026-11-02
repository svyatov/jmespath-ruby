# Compiled query inspection

Status: approved by the user on 2026-11-02.
Scope: [issue #15](https://github.com/svyatov/jmespath-ruby/issues/15).

## Intent and scope

Expose a stable explanation of query structure without evaluating input.
The first identified consumer is [evaluation tracing, issue #16](https://github.com/svyatov/jmespath-ruby/issues/16).
Tracing needs shared operation names and references to operations in the explanation.

This is a bounded library feature with a public recursive data contract and parser metadata work.
It needs a full design because source coordinates and operation identities become compatibility commitments.

Keep syntax nodes, compiled closures, and optimizer decisions private.
Exclude execution traces, schema inference, function validation, readable text rendering, and a CLI inspection flag.
The issue's generic CLI-help requirement does not justify introducing a CLI mode without a specified interface.
Preserve search behavior, options, dependencies, and imported fixtures.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| A1: Immutable hashes and arrays | Ruby callers can traverse and serialize the result | Recursive shape requires documentation and RBS declarations | Selected by the user |
| A2: Public explanation objects | Typed navigation through dedicated methods | More public classes and compatibility commitments | Not selected |
| A3: Readable text first | Direct manual inspection | Tracing still needs structured data | Not selected |

The user selected A1 after the recommendation to include deterministic operation IDs.
The remaining concrete choices below are proposals by the author, subject to approval of this document.

## Public interface

Add `JMESPath::Expression#explain` with no arguments.
It is available after `require "jmespath"` and returns a deeply frozen hash.
The top-level keys are `:source` and `:root`.
`:source` contains the complete query text encoded as UTF-8, including whitespace and trailing newlines.
`:root` contains an explanation node.

For `JMESPath.compile("user.name").explain`, return:

```ruby
{
  source: "user.name",
  root: {
    id: 0,
    operation: "subexpression",
    source_range: [0, 9],
    details: {},
    children: [
      { role: "step", node: {
        id: 1, operation: "field", source_range: [0, 4],
        details: { name: "user" }, children: []
      } },
      { role: "step", node: {
        id: 2, operation: "field", source_range: [5, 9],
        details: { name: "name" }, children: []
      } }
    ]
  }
}
```

All nodes have exactly five keys: `:id`, `:operation`, `:source_range`, `:details`, and `:children`.
Each child entry has exactly two keys: `:role` and `:node`.
Keys use symbols; operation names and child roles use strings.
Decoded field names, function names, and literal values remain ordinary Ruby values.
`JSON.generate(explanation)` produces a representation with string keys and JSON values, without custom serialization methods.

Freeze every nested hash, array, and string, including literal values and literal object keys.
The result must contain no parser objects, execution objects, registry objects, or callbacks.
Repeated calls return equal data; object identity is unspecified.
Inspection of configured and unconfigured expressions with identical source produces equal data.
Calls on a shared expression must not exchange mutable traversal state.

## Operation vocabulary

Child roles identify semantic relationships without exposing private child indexes.
Repeated roles preserve source order.

| Operation | Details | Child roles in traversal order |
| --- | --- | --- |
| `field` | `name: String` | None |
| `current` | Empty | None |
| `literal` | `value: JSON value` | None |
| `group` | Empty | `expression` |
| `subexpression` | Empty | Repeated `step` |
| `pipe` | Empty | Repeated `step` |
| `index` | `index: Integer` | `input` |
| `slice` | `start`, `stop`, `step`, each Integer or nil | `input` |
| `flatten` | Empty | `input` |
| `projection` | Empty | `input`, `expression` |
| `value_projection` | Empty | `input`, `expression` |
| `filter_projection` | Empty | `input`, `condition`, `expression` |
| `expression_reference` | Empty | `expression` |
| `function` | `name: String` | Repeated `argument` |
| `and`, `or` | Empty | Repeated `operand` |
| `not` | Empty | `operand` |
| `comparison` | `operator: String`, one of `==`, `!=`, `<`, `<=`, `>`, `>=` | `left`, `right` |
| `multi_select_list` | Empty | Repeated `element` |
| `multi_select_hash` | Empty | Repeated `entry` |
| `entry` | `name: String` | `expression` |

Slices preserve omitted components as nil, including an omitted step.
Literal contents remain data; they do not become explanation nodes.
Flattening and slices can appear as inputs to projections, matching their language semantics.
Explicit parentheses produce a `group` operation.
Implicit identity expressions produce `current` operations with a nil source range.
Adjacent unparenthesized subexpressions, pipes, and identical boolean operators use ordered, n-ary nodes.
These are documented logical forms, independent of optimizer implementation.

## Identity and evaluation rules

Assign consecutive integer IDs starting at zero by preorder traversal of the public tree.
Visit children in the table's traversal order, including the condition before the filter's projected expression.
IDs identify logical operations, including structural `group` and `entry` nodes.
They are deterministic for identical query text under this contract, independently of evaluation options and cache use.
They are local to an explanation, not persistent identifiers across query edits.
Issue #16 can reference these IDs, including repeated events for one operation.
This issue does not define trace event types or require events for every node.

Traversal order describes structure; runtime behavior follows these rules:

| Operation family | Logical evaluation rule |
| --- | --- |
| Subexpressions and pipes | Evaluate steps left to right, passing each result to the next step. |
| Function calls | Evaluate arguments left to right against the same input, then invoke the function. |
| Expression references | Defer the referenced expression until a function requests evaluation against its chosen value. |
| Projections | Evaluate input, then evaluate the projected expression for each element; omit nil results and retain false. |
| Value projections | Project object values; do not promise object-key sorting. |
| Filters | Evaluate input, evaluate conditions for all elements, then project selected elements; omit nil projected results. |
| Boolean operators | Evaluate operands left to right against the same input, stopping according to JMESPath truth rules. |
| Comparisons | Evaluate left and right against the same input before comparing. |
| Multiselects | Evaluate entries left to right against the same input; nil input returns nil without evaluating entries. |
| Groups and entries | Evaluate their contained expression. |
| Indexes, slices, flattening | Evaluate input before applying the operation. Flattening removes one array level. |
| Fields, current, literals, negation | Apply their standard JMESPath semantics; negation evaluates its operand first. |

Document these rules alongside the vocabulary rather than copying prose into every returned node.
Unknown and custom function names have the same structural representation as built-in names.
The explanation makes no claim about a function's availability, argument types, or callback behavior.

## Source coordinates

Represent source ranges as `[start_byte, end_byte]`, with an inclusive start and exclusive end.
Offsets refer to the returned UTF-8 `:source`, consistent with lexer offsets and function-error byte ranges.
Use `source.byteslice(start_byte...end_byte)` to recover the corresponding text.
Do not add line or column fields; callers can derive them using the established diagnostic conventions.

Explicit operations cover their complete syntactic expression, including delimiters and contained expressions.
Exclude whitespace outside that expression; preserve whitespace inside it.
Field ranges include quotes when the field is quoted.
Group ranges include parentheses; expression-reference ranges include `&`.
Projection ranges include their projected expression.
Filter ranges include their input, brackets, condition, and projected expression.
Index, slice, and flatten ranges include their input when present.
Hash-entry ranges run from the key's opening token through the value expression, excluding separators.

Use nil for synthetic operations without their own complete source expression.
An implicit `current` has no source range; an explicit `@` has its token range.
Overlapping parent and child ranges are expected.
Every non-nil range must be within the source and end on UTF-8 character boundaries.

Parser metadata must distinguish explicit positions from synthetic positions.
Fix inaccurate ranges rather than exposing fabricated offsets from implicit parser nodes.
Preserve language acceptance, evaluation order, nesting behavior, and diagnostic compatibility during that work.
The explanation source uses UTF-8 even when compilation accepts text in another convertible encoding.
Keep `Expression#source` behavior unchanged.

## Implementation constraints and decisions left to the builder

Build the public representation from syntax through a private translator, independently of execution-plan classes.
Keep translation state local to each build.
Do not resolve function definitions or invoke registry extension methods during inspection.
Compilation retains its normal behavior; inspection adds no registry access.

Ordinary compile and search must not build or retain a public explanation unless inspection requests it.
Per-call construction is the default; memoization is optional only if it preserves immutability and avoids unsynchronized mutation of frozen expressions.
File names, private helper decomposition, recursive RBS aliases, and parser metadata representation remain implementation decisions.
Preserve parser metadata used by function diagnostics and compiled execution.

## Verification and documentation

Add focused failing tests through `compile(...).explain` before implementation.
Cover every operation, nested projections, omitted slice bounds, duplicate hash keys, and decoded literals.
Verify the example's exact shape, public traversal order, deterministic IDs, and deep immutability.
Verify configured, uncached, repeated, and concurrent inspection produce equal data without exposing shared mutable state.
Use instrumented callbacks and registries to prove inspection neither evaluates expressions nor resolves function names.

Check ranges using exact expected offsets and extracted substrings.
Cover Unicode, multiline text, CRLF, tabs, trailing whitespace, quoted names, parentheses, and implicit identities.
Cover a convertible non-UTF-8 source and its returned UTF-8 coordinates.
Run regression coverage for syntax diagnostics, function ranges, and nesting limits after parser metadata changes.
Measure compile and ordinary-search impact with the installed benchmark harness if parser changes add work to these paths.

Document the schema, vocabulary, ID scope, evaluation rules, and source coordinates in the compilation guide.
Add a README example and public YARD documentation with executable examples.
Declare recursive explanation data in public RBS without exposing private classes.
Run `bundle exec rake` and `bundle exec rake docs` before claiming implementation complete.
Verify packaged assets if implementation introduces files outside included paths.
