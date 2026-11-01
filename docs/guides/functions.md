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
