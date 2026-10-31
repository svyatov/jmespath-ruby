# Performance

Compile an expression explicitly when evaluating it against many documents.
The convenience cache avoids parsing repeated queries, while explicit compilation also avoids cache lookup.

```ruby
expression = JMESPath.compile("items[*].price | sum(@)")
expression.search({items: [{price: 10}, {price: 20}]}) #=> 30
```

The benchmark task compares one-shot search, repeated search, compiled reuse, and cache churn.
It records interpreter and JIT settings, fixture hashes, elapsed time, and allocated objects.
Only compare runs with the same workload and runtime configuration.
Detailed measurements are added by the benchmark task after both implementations produce matching results.
