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

## Cache behavior

Convenience searches use a synchronized least-recently-used compilation cache.
The cache retains at most 256 expressions and 1,048,576 source bytes.
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
