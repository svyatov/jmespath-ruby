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

`JSON.generate(explanation)` serializes directly, with string keys and JSON values.
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
