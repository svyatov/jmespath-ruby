# Performance

Compile an expression explicitly when evaluating it against many documents.
The convenience cache avoids parsing repeated queries, while explicit compilation also avoids cache lookup.

```ruby
expression = JMESPath.compile("items[*].price | sum(@)")
expression.search({items: [{price: 10}, {price: 20}]}) #=> 30
```

## Measured comparison

These results compare this implementation with jmespath.rb 1.6.2 at commit `5e86ea7da2e954cc12f5b3a8383a43c0a65acba7`.
They are workload-specific measurements, not a general speed guarantee.

The run used MRI 4.0.9 on arm64 macOS, YJIT disabled, 1,000 evaluations per sample, 320 warmup evaluations, and five paired samples.
Each pair alternated implementation order.
Both implementations ran in separate Ruby processes with the same interpreter and inherited locked Bundler environment.
Every sample checked the expected result before timing and after its last evaluation.
Startup samples checked their single evaluation after timing.

The input contains 100 items.
The benchmark covers nested fields, projection, filtering, sorting, slicing, and Unicode.
Fixture SHA-256: `e970e035b16089dec9613f346e0c50a39d716fe08e42998825650ffdc5effacf`.
The checkout contains all raw samples and source fingerprints in `benchmark/results/mri-4.0.9.json`.

Median milliseconds per 1,000 evaluations:

| Workload | Search, new | Search, reference | Compiled, new | Compiled, reference |
| --- | ---: | ---: | ---: | ---: |
| Nested field | 3.700 | 13.995 | 1.962 | 0.751 |
| Projection | 34.144 | 27.230 | 32.458 | 17.944 |
| Filter | 77.085 | 51.176 | 74.001 | 39.887 |
| Sort by key | 113.052 | 100.913 | 111.037 | 80.537 |
| Slice | 8.288 | 18.489 | 6.271 | 3.140 |
| Unicode | 5.507 | 17.025 | 3.557 | 0.969 |

Convenience search improved in three workloads and regressed in three.
Compiled reuse was slower than the reference in all six.
The reference compiled baseline directly visits its optimized syntax, using its private parser API because it has no public `compile` equivalent.
The new compiled API also validates per-call options and input adapters.

Source inspection identifies two likely costs: generic evaluator dispatch on every visited node, and repeated validation around compiled calls.
Stable sorting also builds intermediate key/index pairs.
These observations explain candidate optimization areas; they do not isolate each cost experimentally.
The implementation retains its current architecture and semantics.
No performance optimization was made during this comparison.

Median allocated objects per 1,000 evaluations:

| Workload | Search, new | Search, reference | Compiled, new | Compiled, reference |
| --- | ---: | ---: | ---: | ---: |
| Nested field | 19,007 | 78,012 | 9,007 | 4,007 |
| Projection | 19,007 | 56,020 | 9,007 | 1,007 |
| Filter | 20,007 | 63,016 | 10,007 | 1,007 |
| Sort by key | 333,007 | 230,012 | 323,007 | 109,007 |
| Slice | 22,007 | 87,014 | 12,007 | 5,007 |
| Unicode | 25,007 | 102,011 | 15,007 | 4,007 |

Cold process startup plus one query had medians from 134 to 161 ms for the new library and 134 to 143 ms for the reference.
Startup allocations measure only the query after library loading; startup time includes process creation, Bundler, loading, and the query.
They are not total process allocation or memory measurements.

Cache churn cycles through 320 distinct, equivalent expressions.
This exceeds the new cache's 256-entry capacity but fits the reference's larger cache.
New/reference median milliseconds were 40.317/43.549 for fields, 69.065/58.360 for projection, 113.641/81.334 for filters, 169.756/136.768 for sorting, 50.444/48.471 for slicing, and 53.364/48.235 for Unicode.
This mode compares the documented cache policies under the same query stream, not equal cache capacities.

## Reproduce

Prepare an explicit checkout of the pinned reference, including its `lib` directory and `VERSION` file.
The harness performs no downloads or installs.

```sh
bundle exec ruby script/benchmark.rb --ruby-root /path/to/jmespath.rb --iterations 1000 --output /tmp/jmespath-benchmark.json
```

Use `--only field` for one workload and `--rounds 5` to set the pair count.
Compare results only when the interpreter, JIT, fixture hashes, and source fingerprints match.
Host load and garbage collection can affect timing; use the raw samples when evaluating small differences.
