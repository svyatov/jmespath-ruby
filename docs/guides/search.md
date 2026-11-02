# Search semantics

JMESPath expressions select and transform structured values.
The [language specification](https://jmespath.org/specification.html) defines the grammar and standard functions.

## Fields and indices

```ruby
JMESPath.search("user.name", {user: {name: "Ada"}}) #=> "Ada"
JMESPath.search("items[-1]", {items: [10, 20, 30]}) #=> 30
JMESPath.search("items[99]", {items: [10]}) #=> nil
```

Hash fields accept string and existing symbol keys.
A non-nil string value wins when both forms exist.
A nil string value allows fallback to the symbol key.
Struct lookup visits members, not arbitrary methods.

## Projections and flattening

A projection applies its right expression to each input element.
Nil results are omitted; false results remain present.

```ruby
JMESPath.search("[*].value", [{value: 1}, {}, {value: false}]) #=> [1, false]
JMESPath.search("[]", [[1, 2], [3, [4]]]) #=> [1, 2, 3, [4]]
JMESPath.search("[*].value | [0]", [{value: 1}, {value: 2}]) #=> 1
```

Flattening removes one array level.
A pipe evaluates its right expression against the entire left result, ending projection propagation.

## Filters and truthiness

False, nil, empty strings, empty arrays, and empty objects are false values.
Zero is true in JMESPath.

```ruby
JMESPath.search("items[?enabled].id", {items: [{id: 1, enabled: true}, {id: 2, enabled: false}]}) #=> [1]
JMESPath.search("a || b", {a: [], b: "fallback"}) #=> "fallback"
JMESPath.search("!value", {value: 0}) #=> false
```

Boolean operators short-circuit and return the selected operand.

## Slices and constructed values

```ruby
JMESPath.search("[::-1]", [1, 2, 3]) #=> [3, 2, 1]
JMESPath.search("[:0:-1]", [1, 2, 3]) #=> [3, 2]
JMESPath.search("{name: user.name, missing: absent}", {user: {name: "Ada"}}) #=> {"name" => "Ada", "missing" => nil}
```

An omitted negative-slice stop differs from an explicit `-1`.
A zero slice step raises InvalidValueError.
Multiselects construct new arrays or hashes and retain explicit nil values.

## Search results

Use `Expression#try_search` when an integration needs to display library-owned failures without rescuing exceptions.
The frozen `JMESPath::SearchResult` exposes `success?`, `value`, and `error`.
Successful null and false remain successful values:

```ruby
query = JMESPath.compile("name")
query.try_search({}).success? #=> true
query.try_search({}).value #=> nil
query.try_search({name: false}).value #=> false
query.try_search({name: false}).error #=> nil
failure = JMESPath.compile("length(name)").try_search({name: nil})
failure.success? #=> false
failure.value #=> nil
failure.error.is_a?(JMESPath::Errors::InvalidTypeError) #=> true
```

The container retains selected value identity without copying or freezing the value.
Failures retain the original exception, metadata, and backtrace without freezing the exception.
Each call evaluates once, with the same inputs and evaluation options as `search`.
See [failure ownership](errors.md#failure-results) and [compiled result handling](compilation.md#failure-results).
