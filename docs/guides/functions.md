# Functions

Function arguments are evaluated before type validation.
Expression references, written as `&expression`, defer evaluation until a function supplies an input.

## Standard functions

Validation failures expose the full signature, rejected type, argument position, and optional source range.
See [function validation data](errors.md#function-validation-data) for examples and nullable fields.
Checks inside built-ins can impose narrower constraints than their declared signatures.
For example, `sort_by`, `min_by`, and `max_by` require expression-reference results to have one consistent number or string type.

| Function | Accepted arguments | Result |
| --- | --- | --- |
| `abs` | number | Absolute value |
| `avg` | array of numbers | Mean, or nil for an empty array |
| `ceil` | number | Integer rounded upward |
| `floor` | number | Integer rounded downward |
| `contains` | string or array, value | Membership boolean |
| `ends_with` | string, string | Suffix boolean |
| `starts_with` | string, string | Prefix boolean |
| `length` | string, array, or object | Character or element count |
| `reverse` | string or array | Reversed value |
| `join` | string separator, array of strings | Joined string |
| `keys` | object | String keys |
| `values` | object | Values |
| `merge` | one or more objects | Object with later values winning |
| `map` | expression reference, array | Mapped values, including nil |
| `min` | homogeneous array of numbers or strings | Minimum, or nil |
| `max` | homogeneous array of numbers or strings | Maximum, or nil |
| `sort` | homogeneous array of numbers or strings | Stable sorted array |
| `sort_by` | array, expression reference | Stable array sorted by homogeneous keys |
| `min_by` | array, expression reference | Input element with minimum key, or nil |
| `max_by` | array, expression reference | Input element with maximum key, or nil |
| `sum` | array of numbers | Sum, including zero for an empty array |
| `not_null` | one or more values | First non-nil value |
| `to_array` | value | Array, preserving arrays |
| `to_number` | value | Number when convertible, otherwise nil |
| `to_string` | value | String or compact JSON representation |
| `type` | value | JMESPath type name |

```ruby
JMESPath.search("map(&name, @)", [{name: "Ada"}, {}]) #=> ["Ada", nil]
JMESPath.search("sort_by(@, &age)[*].name", [{name: "Lin", age: 20}, {name: "Ada", age: 10}]) #=> ["Ada", "Lin"]
JMESPath.search("avg(@)", [1, 2, 3]) #=> 2.0
```

## Command-line reference

Run either executable from the shell to list built-in signatures and descriptions without reading stdin:

```sh
jmespath --functions
jmespath.rb --functions
```

Each built-in appears once in alphabetical order, using public function metadata.
For example, the listing includes these entries:

```text
join(string, array<string>) Join strings with a separator.
length(string|array|object) Character or element count.
map(expref, array) Map an expression over an array, including null results.
merge(object...) Merge objects, with later values winning.
sort(array<number>|array<string>) Stable sorted array of numbers or strings.
```

`A|B` accepts either type; `any` accepts any value.
`array<T>` requires every element to have type `T`, while `array` accepts elements of any type.
Thus `array<number>|array<string>` accepts a homogeneous array, including an empty array.
`expref` denotes an expression reference written as `&expression`.
The final `...` marks a required argument that repeats, so `merge(object...)` needs at least one object.
The listing includes a notation legend and describes declared types; runtime checks can impose narrower constraints.
Return types are not inferred.

Use `--functions` alone, without queries, paths, other modes, repeated flags, or values.
The exact two-argument form `--validate --functions` validates the literal query text under the validation rules.
Listing returns status 0 with empty stderr; output failures return status 1.
Usage failures return status 2 with empty stdout and usage guidance on stderr, before accessing input.

## Custom signatures

Start with `Functions.default` to retain the built-ins, or `Functions.new` for an empty registry.
Use an array of accepted type symbols for each argument.
Type symbols are `:any`, `:null`, `:boolean`, `:number`, `:string`, `:array`, `:object`, and `:expref`.
Typed arrays use `:array_number` or `:array_string`.
A union of those array types accepts either homogeneous array, including an empty array.

```ruby
functions = JMESPath::Functions.default.with("size_or_zero", signature: [[:string, :null]]) do |value|
  value.nil? ? 0 : value.length
end
JMESPath.search("size_or_zero(missing)", {}, functions: functions) #=> 0
```

With `variadic: true`, the final argument signature repeats and remains required.
Every supplied argument is checked.
Duplicate names require `override: true`.
Registration returns a new frozen registry and leaves the original intact.

Callbacks receive evaluated Ruby values and may retain selected object identity.
Return a supported value and avoid mutating shared input.
Callback exceptions propagate with their original object and backtrace.

## Registry inspection

Use `names` to list functions in the active registry, including custom registrations and overrides.
Names use ascending, case-sensitive lexical order.
An empty registry returns an empty array.

Use these calls in Ruby to register a description and inspect the function:

```ruby
functions = JMESPath::Functions.new.with("double", signature: [[:number]], description: "Double a number.") do |value|
  value * 2
end
functions.names #=> ["double"]
metadata = functions.metadata("double")
metadata.name #=> "double"
metadata.signature #=> [[:number]]
metadata.variadic? #=> false
metadata.description #=> "Double a number."
functions.metadata("missing") #=> nil
JMESPath::Functions.default.metadata("length").description #=> "Character or element count."
```

`metadata(name)` returns a `JMESPath::Functions::Metadata` record, or `nil` if the function is absent.

| Field | Meaning |
| --- | --- |
| `name` | Function identifier |
| `signature` | Accepted type symbols for each declared argument |
| `variadic?` | Whether the final declared argument repeats and remains required |
| `description` | Optional string, or `nil` when omitted |

Signatures preserve unions and typed arrays such as `[:string, :null]` and `[:array_number]`.
They describe declared arguments; runtime checks can impose further constraints, such as homogeneous results from a `sort_by` expression.
Return types are not inferred.

All built-ins have descriptions.
Custom descriptions accept strings, including empty strings, or `nil`.
Other values raise `ArgumentError`.
An override replaces all metadata, so omitting its description yields `nil`.

Inspection does not invoke function implementations.
The returned arrays, records, strings, and nested signature arrays are frozen.
Registration copies supplied strings and signature arrays without freezing the caller's objects.
Later registrations or changes to supplied inputs cannot alter earlier snapshots.
Shared registries support concurrent inspection; object identity across inspection calls is not guaranteed.

## Unknown function suggestions

An unknown function raises `UnknownFunctionError` with up to three similar names from the active registry.
Candidates include custom functions; overrides appear once.
Empty registries and unrelated names yield no suggestions.
Names from other registries are excluded.

Matching is case-sensitive and uses optimal string alignment distance.
Insertion, deletion, replacement, and an adjacent letter swap each cost one edit.
The same substring cannot be edited twice, which distinguishes this distance from unrestricted transposition matching.
The maximum distance is one when the longer name has at most four characters, and two otherwise.
Candidates are ranked by ascending distance, then ascending lexical order.

Suggestions inspect registered names without executing candidate callbacks.
Function lookup happens during evaluation, after the arguments have been evaluated.
Compilation does not reject an unavailable function, and suggestions never correct or execute a query automatically.
See [unknown function data](errors.md#unknown-function-data) for structured fields and messages.
