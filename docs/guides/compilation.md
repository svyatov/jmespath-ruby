# Compilation and concurrency

`JMESPath.compile` parses an expression into an immutable `JMESPath::Expression`.
Each call to `Expression#search` reuses that syntax with separate evaluation state.

```ruby
expression = JMESPath.compile("items[*].name")
expression.search({items: [{name: "Ada"}]}) #=> ["Ada"]
expression.search({items: [{name: "Lin"}]}) #=> ["Lin"]
```

The expression owns a frozen copy of the query text.
Changing the caller's original string does not change the compiled expression.
Mutable literal results are copied for each evaluation.

## Failure results

`Expression#try_search` reuses compiled syntax and saved evaluation options, with per-call overrides handled independently.
Calls return separate frozen results and isolate capture state across nested calls, threads, and fibers.
The returned value or error retains its identity and independent mutability.
See [search results](search.md#search-results) for the result fields.

A custom function can handle an inner query failure explicitly:

```ruby
inner = JMESPath.compile("length(@)")
functions = JMESPath::Functions.default.with("checked", signature: [[:any]]) do |value|
  result = inner.try_search(value)
  result.success? ? result.value : "invalid"
end
outer = JMESPath.compile("checked(@)", functions: functions)
outer.try_search(4).value #=> "invalid"
outer.try_search([1, 2]).value #=> 2
```

An exception escaping the custom function propagates from the outer call, even when it came from an inner query.

## Required results

Call `Expression#fetch` when a Ruby caller requires a non-null final result.
It accepts the same inputs, positional options, and keyword options as `search`, including saved defaults and per-call overrides.
Each call evaluates once and returns any non-nil result unchanged, preserving selected object identity and mutability.
False, zero, empty strings, empty arrays, and empty hashes succeed.

Use these calls in Ruby code:

```ruby
query = JMESPath.compile("user.name")
query.fetch({user: {name: "Ada"}}) #=> "Ada"
query.fetch({user: {name: false}}) #=> false
query.fetch({}) # raises JMESPath::Errors::NullResultError
query.fetch({user: {name: nil}}) # raises JMESPath::Errors::NullResultError
```

Missing fields, explicit null, and out-of-range indexes produce the same error.
Only the final result must be non-null; intermediate null values can be replaced by the query.
With `disable_visit_errors: true`, suppressed type or arity failures producing nil also raise `NullResultError`.
Other failures propagate unchanged.
The error exposes frozen query text through `expression` and uses the message `Expression returned null`.
It contains no input document or explanation of the null result.
Nullable `search` and `call` behavior is unchanged.

## Query inspection

Call `Expression#explain` to inspect query structure without providing input data.
Inspection neither resolves function names nor executes callbacks.
Unknown and custom function names remain valid structure; inspection cannot establish availability, argument types, or callback behavior.

```ruby
query = JMESPath.compile("user.name")
query.explain[:root][:operation] #=> "subexpression"
query.explain[:root][:children].map { |child| child[:node][:details][:name] } #=> ["user", "name"]
query.explain[:root][:source_range] #=> [0, 9]
```

The returned hash has two keys: `:source`, containing the complete UTF-8 query text, and `:root`, containing a logical operation.
Every operation has these keys:

| Key | Value |
| --- | --- |
| `:id` | Integer identifying the operation within this explanation |
| `:operation` | String from the operation table below |
| `:source_range` | Two byte offsets, `[start_byte, end_byte]`, or nil |
| `:details` | Hash containing operation-specific values |
| `:children` | Ordered array of `{role: String, node: operation_hash}` entries |

All hashes, arrays, and strings are frozen, including literal object keys and nested literal values.
Repeated inspection produces equal data; object identity is unspecified.
Saved evaluation options and cache settings do not affect the explanation.
Compiled expressions support concurrent inspection with separate traversal state.
Inspection exposes neither private syntax nodes nor optimizer operations.
Ordinary compilation and evaluation do not construct explanations.

### Operations and child roles

Keys use symbols; operation names and child roles use strings.
Decoded names and literal values retain their Ruby representations.
Literal contents remain values, without additional operation nodes.
Empty details are represented by `{}`.

| Operation | Details | Child roles in traversal order |
| --- | --- | --- |
| `field` | `name: String` | None |
| `current` | Empty | None |
| `literal` | `value: decoded Ruby value` | None |
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

Repeated roles preserve source order, including duplicate hash entries.
Omitted slice components remain nil, including an omitted step.
Flattening and slicing can appear as inputs to projections.
Explicit parentheses produce `group` nodes; implicit identities produce `current` nodes.
Adjacent unparenthesized subexpressions, pipes, and identical boolean operators form ordered nodes with multiple children.

### Operation IDs and evaluation rules

IDs start at zero and increase consecutively in preorder: each operation, then its children in the table's order.
Filter conditions precede projected expressions in this traversal.
IDs include structural groups and hash entries.
Identical query text produces identical IDs under this contract, independently of evaluation options or cache use.
IDs are local to an explanation and do not identify operations across query edits.

Traversal order describes structure, with these logical evaluation rules:

| Operation family | Evaluation rule |
| --- | --- |
| Subexpressions and pipes | Evaluate steps left to right, passing each result to the next step. |
| Function calls | Evaluate arguments left to right against the same input, then invoke the function. |
| Expression references | Defer the referenced expression until a function requests evaluation against its chosen value. |
| Projections | Evaluate input, then project each element; omit nil results and retain false. |
| Value projections | Project object values without promising sorted object keys. |
| Filters | Evaluate input, evaluate conditions for all elements, then project selected elements; omit nil projected results. |
| Boolean operators | Evaluate operands left to right against the same input, stopping according to JMESPath truth rules. |
| Comparisons | Evaluate both operands against the same input before comparing, left before right. |
| Multiselects | Evaluate entries left to right against the same input; nil input returns nil without evaluating entries. |
| Groups and entries | Evaluate their contained expression. |
| Indexes, slices, flattening | Evaluate input before applying the operation; flattening removes one array level. |
| Fields, current, literals, negation | Apply standard JMESPath semantics; negation evaluates its operand first. |

The explanation contains no input values, evaluation events, or optimizer details.

### Source coordinates and serialization

Ranges include the start byte and exclude the end byte in the returned UTF-8 `:source`.
They use the same coordinate units as lexer offsets and function-error byte ranges.
Use `source.byteslice(start_byte...end_byte)` to extract the text.
Inspection retains all source whitespace, including trailing newlines.
Convertible non-UTF-8 query text is encoded as UTF-8 in the explanation; `Expression#source` retains its original encoding.

Explicit operation ranges cover their entire syntactic expression, including delimiters and contained expressions.
They exclude surrounding whitespace and retain internal whitespace.
Quoted fields include quotes, groups include parentheses, and references include `&`.
Projections include their projected expression; filters also include the input, brackets, and condition.
Index, slice, and flatten ranges include their input when present.
Hash-entry ranges include the key and value expression, excluding separators.
Parent and child ranges can overlap.

Implicit `current` operations have nil ranges; an explicit `@` has its token range.
Every non-nil range stays within the source and ends on UTF-8 character boundaries.
Line and column fields are omitted; derive them using the [syntax diagnostic conventions](errors.md).

For finite numeric values, `JSON.generate(explanation)` serializes directly, with string keys and JSON values.
Numeric overflow literals preserve their decoded non-finite Ruby floats, including values inside literal arrays and objects.
Strict JSON cannot represent these values; generation raises `JSON::GeneratorError`, even with `max_nesting: false`.
Inspection preserves those values and compilation behavior without substituting strings or nulls.
Deep explanation trees can exceed JSON's default nesting limit before reaching the query's supported depth limit.
Use `JSON.generate(explanation, max_nesting: false)` for these trees.
Use the corresponding option when parsing the serialized explanation.
For example, this Ruby code reads the root operation after serialization:

```ruby
explanation = JMESPath.compile("user.name").explain
JSON.parse(JSON.generate(explanation))["root"]["operation"] #=> "subexpression"
```

This Ruby example serializes an explanation with nested groups:

```ruby
explanation = JMESPath.compile("(" * 128 + "@" + ")" * 128).explain
serialized = JSON.generate(explanation, max_nesting: false)
JSON.parse(serialized, max_nesting: false)["root"]["operation"] #=> "group"
```

This Ruby example inspects an overflow literal without serializing it:

```ruby
query = JMESPath.compile("`1e400`")
query.explain[:root][:details][:value].infinite? #=> 1
query.search(nil).infinite? #=> 1
```

## Evaluation tracing

Call `Expression#trace` to evaluate once and explain null fields, filter exclusions, and omitted projection results.
It accepts the same input forms and evaluation options as `search`, including saved defaults and per-call overrides.
The keyword `limit:` sets a positive Integer event limit, defaulting to 1,000.
Invalid limits raise `ArgumentError` before consuming input; positional `:limit` is not an evaluation option.

This Ruby example traces a projection while retaining false values:

```ruby
query = JMESPath.compile("items[*].name")
report = query.trace({items: [{name: "Ada"}, {}, {name: false}]})
report[:value] #=> ["Ada", false]
report[:events].map { |event| event[:type] } #=> ["field_null", "projection_omission"]
report[:events].first[:context] #=> [{operation_id: 0, index: 1}]
report[:truncated] #=> false
```

### Report and event format

The frozen report has exactly three keys:

| Key | Value |
| --- | --- |
| `:value` | The ordinary query result, including nil or false |
| `:events` | A deeply frozen array of diagnostic events |
| `:truncated` | True when a diagnostic event was discarded because the limit was reached |

The result retains ordinary mutability and selected input object identity.
Freezing the report does not freeze its `:value`.
Diagnostics contain no input objects, intermediate query values, or document snapshots.

Every event has exactly four keys:

| Key | Value |
| --- | --- |
| `:type` | A string from the event table below |
| `:operation_id` | The responsible operation's ID in `query.explain` |
| `:context` | An ordered array of enclosing iteration frames |
| `:details` | A hash of event-specific details |

Event and detail keys are symbols; type and reason values are strings.

| Type | Responsible operation | Details |
| --- | --- | --- |
| `field_null` | The field access returning nil | `name: String` and `reason: String` |
| `filter_exclusion` | The filter rejecting an item | Empty hash |
| `projection_omission` | The projection omitting a nil result | Empty hash |

Field reasons are `missing`, `null`, `non_object`, and `unknown`.
`missing` means lookup established absence under string-key and symbol-key fallback rules.
`null` means lookup established an explicitly present nil under those rules.
`non_object` means ordinary conversion produced no object.
`unknown` means classification would require additional observable operations.
Custom lookup methods and identity-based hashes receive conservative `unknown` classifications.
Tracing adds no conversions, application callbacks, or application-observable field lookups to refine a reason.

This Ruby example finds the source of an omission through its operation ID:

```ruby
query = JMESPath.compile("items[*].name")
report = query.trace({items: [{}]})
event = report[:events].last
query.explain[:root][:id] == event[:operation_id] #=> true
query.explain[:root][:source_range] #=> [0, 13]
```

Successful fields, retained values, out-of-range indexes, and unvisited branches produce no diagnostics.
Tracing explains the three event types above; it does not explain every possible nil result.
Field events precede any exclusion or omission they cause.
Filters evaluate all conditions before projecting selected items.

### Local item context

Each context frame has exactly `:operation_id` and `:index`.
Frames run from the outermost iteration to the innermost.
Indexes are zero-based positions in the immediate array or object-values sequence.
Filter projections retain original input indexes, including gaps left by rejected items.
An exclusion or omission includes the frame of its affected item.
Events outside iteration have an empty context.

Object projections use ordinal values positions without extra key enumeration.
Pipes, slicing, flattening, and functions can establish local sequences.
Context does not provide object keys or paths back through transformations to the original document.

Expression-reference frames identify the reference operation and its zero-based invocation count within that trace call.
The count describes callback invocation order, not positions in a function's input.
Synchronous reference calls retain enclosing iteration frames.
Concurrent reference calls keep separate thread contexts; application scheduling determines event order.
References saved by callbacks remain callable after tracing finishes, with collection closed.

### Limits, errors, and isolation

Tracing retains the first `limit` diagnostic events in observed evaluation order.
Exactly `limit` events leave `:truncated` false; the next diagnostic sets it to true.
Truncation adds no sentinel event.
Evaluation continues normally after the limit, preserving callback counts, order, and the complete result.

This Ruby example limits diagnostics without changing the result:

```ruby
query = JMESPath.compile("items[*].name")
limited = query.trace({items: [{}, {name: false}]}, limit: 1)
limited[:value] #=> [false]
limited[:events].length #=> 1
limited[:truncated] #=> true
```

The limit bounds retained diagnostics, not evaluation memory.
The operation map uses memory proportional to query size; retained events contain copies of their enclosing frames.
Filters retain selected original indexes until projection finishes.
Collection avoids further event snapshots after truncation.

Trace state is separate for each call, including concurrent calls and nested calls from callbacks.
Ordinary search builds no trace collector or operation map.
Tracing propagates original evaluation and input exceptions without attaching a report or retrying evaluation.
Suppression retains its ordinary behavior; a suppressed nil result can produce a downstream omission.
There is no dedicated validation-failure event, automatic logging, or module-level trace method.
Interactive sessions expose tracing through `:trace QUERY`; see the [command-line guide](command-line.md#interactive).

## Saved options

Pass `functions:` and `disable_visit_errors:` to `compile` to save defaults for repeated searches.
Configuration is validated once, and compiled operations use the selected registry.
The `call` method is an alias for `search`.

```ruby
functions = JMESPath::Functions.default.with("double", signature: [[:number]]) { |value| value * 2 }
query = JMESPath.compile("double(price)", functions: functions, disable_visit_errors: true)
query.call({price: 12}) #=> 24
query.search({price: nil}) #=> nil
query.search({price: 7}, disable_visit_errors: false) #=> 14
```

Per-call options override the saved values for that call only.
Omitted options retain their saved values.
Conflicting positional and keyword options raise `ArgumentError`.
Custom registries and configured expressions never enter the shared syntax cache.
Unknown function names still raise during evaluation, after their arguments are evaluated.

## Cache behavior

Convenience searches use a synchronized least-recently-used compilation cache.
The cache retains at most 32 expressions and 1,048,576 source bytes.
Oversized expressions are parsed without entering the cache.
Failed parses, input documents, search results, and custom registries are never cached.

```ruby
JMESPath.search("x", {x: 1}, cache_expressions: false) #=> 1
JMESPath.compile("x", cache_expressions: false).search({x: 2}) #=> 2
```

Disabling caching changes parsing cost, not query semantics.
The same option is accepted by a compiled expression; it already owns parsed syntax.

## Threads and callbacks

Compiled expressions and immutable function registries can be shared between threads.
Callers must synchronize changes to input objects and state captured by custom callbacks.
Returned input objects remain caller-owned and mutable.
The library does not provide callback timeouts or a security sandbox.

## Nesting

The default and maximum supported nesting limit is 128.
Use `max_depth` to select a smaller positive limit when compiling or searching.
A compiled expression validates a requested search limit without reparsing.
Flat field chains and pipes use iterative evaluation.
