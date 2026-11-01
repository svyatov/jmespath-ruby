# Performance

For the current comparison across published Ruby implementations, see [implementation comparison](comparison.md).
The measurements below preserve earlier revisions, private-node diagnostics, and memory experiments against jmespath.rb.

Compile an expression explicitly when evaluating it against many documents.
The convenience cache avoids parsing repeated queries, while explicit compilation also avoids cache lookup.

```ruby
expression = JMESPath.compile("items[*].price | sum(@)")
expression.search({items: [{price: 10}, {price: 20}]}) #=> 30
```

## Reproduce

Prepare a checkout of [jmespath.rb at commit 5e86ea7](https://github.com/jmespath/jmespath.rb/tree/5e86ea7da2e954cc12f5b3a8383a43c0a65acba7).
The harness performs no downloads or installs.

```sh
bundle exec ruby script/benchmark.rb --ruby-root /path/to/jmespath.rb --iterations 2000 --rounds 5 --memory --output /tmp/jmespath-benchmark.json
```

The default suite includes all 12 cases from the four upstream benchmark files and six supplemental workloads.
Upstream files remain unchanged; `benchmark/upstream/sources.json` records their commit, license, and SHA-256 hashes.
Each workload runs in startup, repeated search, cached runtime reuse, direct compiled reuse, and cache-churn modes.
Use `--only field` to select one workload.

Cached runtime reuse compares `Expression#search` with the reference's persistent `Runtime#search`, following its `benchmark:cached` task.
Direct compiled reuse compares `Expression#search` with the reference's optimized node, bypassing its runtime.

The `--memory` option requires macOS `/usr/bin/time -l` and `ps`.
Omit that option to measure timing and allocations without the macOS memory tools.
Startup timing with `--memory` includes memory reporting; omit it when measuring cold latency alone.

## Measurements

These measurements compare revision `367f256e81f31ebff698466b768da0164610dd03` with the pinned jmespath.rb reference on arm64 macOS.
Each run uses default GC settings, disabled YJIT, and no Bundler.
Each sample performs 320 warmup evaluations and 2,000 measured evaluations, except startup samples.
Three paired samples alternate implementation order in separate processes using the same Ruby interpreter.

All 18 workloads have lower median times in repeated search, cached runtime reuse, and cache churn on each tested Ruby version.
Speedup is reference time divided by library time; larger values indicate faster execution.
Peak RAM includes process startup and warmup.

| MRI | Repeated search | Cached runtime reuse | Cache churn | Largest peak RAM increase across these modes |
| --- | ---: | ---: | ---: | ---: |
| 3.3.11 | 1.40x to 86.51x | 1.10x to 79.11x | 1.19x to 2.48x | 2.36 MiB (12.3%) |
| 3.4.9 | 1.38x to 85.23x | 1.11x to 76.47x | 1.19x to 2.48x | 3.52 MiB (17.4%) |
| 4.0.9 | 1.35x to 74.36x | 1.04x to 70.93x | 1.16x to 2.27x | 1.25 MiB (5.4%) |

Cached runtime reuse follows the upstream cached benchmark: this library reuses an `Expression`, and the reference reuses a `Runtime`.
The implementations return the same checked results, including the upstream cases and six supplemental workloads.

Raw samples, runtime metadata, and source fingerprints are available for
[MRI 3.3.11](../../benchmark/results/mri-3.3.11-speed.json),
[MRI 3.4.9](../../benchmark/results/mri-3.4.9-speed.json), and
[MRI 4.0.9](../../benchmark/results/mri-4.0.9-speed.json).

Longer checks use 20,000 evaluations, five paired samples, and no memory collection.
Cached `wildcard_with_field_match2` is 1.10x faster on MRI 4.0.9; cached `multi_wildcard_field` is 1.44x faster on MRI 3.3.11.
The [follow-up samples](../../benchmark/results/cached-margin-checks.json) check the smallest cached speed margin and a noisy sample from the full runs.

### Saved query options

Revision `bb075c70dd86cd52d6b91c6ab2acb0f9f6e916a6` adds saved evaluation options to compiled queries.
These measurements compare saved options with per-call options on that revision and on the preceding implementation, `f73c7e4`.
Each workload uses five alternating samples, 640 warmup searches, and 10,000 measured searches in separate processes.
All runs use default GC settings, disabled YJIT, no Bundler, and arm64 macOS.
Results are checked before and after timing.

| MRI | Speedup over preceding per-call options | Speedup over same-revision per-call options | Largest peak RAM increase over preceding version |
| --- | ---: | ---: | ---: |
| 3.3.11 | 1.57x to 7.49x | 1.59x to 7.85x | 2.48 MiB |
| 3.4.9 | 1.55x to 8.25x | 1.58x to 8.87x | 7.08 MiB |
| 4.0.9 | 1.49x to 6.41x | 1.49x to 6.73x | 2.08 MiB |

The seven cases cover field traversal, projection, a custom function, an unchanged built-in, a built-in override, and valid and invalid suppressed calls.
They use the `items` document in `benchmark/documents.json` and these configurations:

| Case | Expression | Saved options |
| --- | --- | --- |
| Field | `meta.owner.name` | Registry extended with `double` |
| Projection | `items[*].price` | Registry extended with `double` |
| Custom | `double(items[3].price)` | Registry extended with `double` |
| Unchanged built-in | `length(text)` | Registry extended with `double` |
| Override | `length(text)` | Override `length` to return twice the string length |
| Suppressed | `length(text)` | `disable_visit_errors: true` |
| Invalid | `length(items[0].active)` | `disable_visit_errors: true` |

The `double` function accepts one number and returns twice its value; the override accepts one string.
On MRI 4.0, field lookup drops from six allocated objects per search in the preceding version to one with saved options.
Peak RAM includes process startup and warmup; it is measured with macOS `/usr/bin/time -l`.
The largest increase is projection on MRI 3.4: 27.66 MiB versus 20.58 MiB.
Saving options reduces temporary allocations, but the default GC schedule can retain more array memory between collections.

Default search controls cover all 18 existing workloads.
Their median speed ratios range from 0.99x to 1.09x for public search and 0.97x to 1.10x for compiled search, excluding one short-run outlier.
That MRI 3.3 deep-query outlier initially measured 0.94x; seven paired 100,000-search samples measured 1.001x.
This does not establish a regression in that workload.

Raw samples and source fingerprints: [MRI 3.3.11](../../benchmark/results/configured-mri-3.3.11.json),
[MRI 3.4.9](../../benchmark/results/configured-mri-3.4.9.json), [MRI 4.0.9](../../benchmark/results/configured-mri-4.0.9.json),
and the [deep-query recheck](../../benchmark/results/configured-deep-recheck.json).

### Direct-node diagnostics

The `compiled` mode calls the reference's private optimized node directly, bypassing its runtime API.
This library still calls `Expression#search`, which supports per-call options and input adapters.
This stricter comparison does not show a speedup for every workload:

| MRI | Workloads faster | Workloads without a median speedup |
| --- | ---: | --- |
| 3.3.11 | 17 of 18 | `single_expression` |
| 3.4.9 | 17 of 18 | `single_expression` |
| 4.0.9 | 15 of 18 | `single_expression`, `wildcard_with_field_match`, `wildcard_with_field_match2` |

Startup samples include memory-reporting overhead and do not establish pure load-time improvements.

## Earlier measurements

These workload-specific measurements compare revision `2d061978319b7757443e52c5aba01992ab8c34b0` with jmespath.rb 1.6.2 on MRI 4.0.9, arm64 macOS, with YJIT disabled.
Each sample performs 320 warmup evaluations and 2,000 measured evaluations, except startup samples, which perform one evaluation without warmup.
Five paired samples alternate implementation order.
Implementations run in separate processes using the same Ruby interpreter and Bundler environment.
Expected results are checked before and after timing; startup checks its result after timing.
The harness rejects source or fixture changes during a run.

Raw samples, runtime details, and source fingerprints are in [mri-4.0.9-optimized.json](../../benchmark/results/mri-4.0.9-optimized.json).
The earlier, unoptimized baseline remains in [mri-4.0.9.json](../../benchmark/results/mri-4.0.9.json).

Search speedup is reference time divided by library time; values above 1 indicate faster execution.
Tables show median allocations per 2,000 searches and whole-process peak resident memory, including startup and warmup.
Memory collection occurs outside the timed search loop.
Retained Ruby object bytes are also recorded after full garbage collection; they exclude some native allocations and are not process RAM.
Allocation counts alone do not establish lower RAM usage.

18 of 18 workloads were faster; 17 had equal or lower median peak RAM.

### Upstream workloads

| Workload | Search speedup | Peak RAM, library / reference (MiB) | Allocations, library / reference |
| --- | ---: | ---: | ---: |
| single_expression | 2.70x | 29.12 / 29.88 | 6007 / 46011 |
| single_dot_expression | 4.81x | 28.97 / 29.64 | 6007 / 102015 |
| double_dot_expression | 6.98x | 29.02 / 29.67 | 6007 / 148017 |
| dot_no_match | 7.97x | 29.02 / 29.86 | 6007 / 196023 |
| deep_nesting_10 | 17.10x | 29.08 / 30.02 | 6007 / 526029 |
| deep_nesting_50 | 57.57x | 29.30 / 30.78 | 6007 / 4546109 |
| deep_nesting_50_pipe | 56.31x | 29.39 / 31.00 | 6007 / 4546109 |
| deep_nesting_50_index | 28.36x | 29.25 / 30.11 | 6007 / 4950009 |
| multi_wildcard_field | 4.59x | 29.16 / 29.92 | 12007 / 166041 |
| wildcard_with_index | 5.81x | 29.03 / 29.91 | 8007 / 222051 |
| wildcard_with_field_match | 3.83x | 29.19 / 30.08 | 8007 / 104020 |
| wildcard_with_field_match2 | 4.18x | 29.03 / 29.98 | 8007 / 110028 |

### Supplemental workloads

| Workload | Search speedup | Peak RAM, library / reference (MiB) | Allocations, library / reference |
| --- | ---: | ---: | ---: |
| field | 7.29x | 28.84 / 29.72 | 6007 / 156016 |
| projection | 1.61x | 30.80 / 30.23 | 8007 / 112032 |
| filter | 1.44x | 30.05 / 30.39 | 8007 / 126016 |
| sort | 1.18x | 29.75 / 29.88 | 226007 / 460012 |
| slice | 3.55x | 29.50 / 29.83 | 14007 / 174018 |
| unicode | 4.80x | 29.31 / 29.84 | 22007 / 204015 |

### Compiled reuse and cache churn

Compiled reuse: 2 of 18 workloads were faster; 17 had equal or lower median peak RAM.
Cache churn: 18 of 18 workloads were faster; 11 had equal or lower median peak RAM.

The reference compiled baseline visits its optimized tree through a private API because it has no public `compile` equivalent.
`Expression#search` also supports per-call options and input adapters.
These operations are reported separately from the public `JMESPath.search` comparison.

Churn cycles through 320 distinct expressions, exceeding the library's 32-entry cache.
The reference constructs a runtime and parser for each public search, so its cache does not persist between those calls.
This mode tests the same query stream against each implementation's public behavior.

### Default GC across supported MRI series

The earlier implementation did not meet strict peak-RAM parity on MRI 3.3, 3.4, and 4.0.
Public search is faster in all 18 workloads on each tested version, but some workloads use more peak RAM.
The implementation remains pure Ruby; these comparisons exclude application-level GC tuning.

Additional runs use MRI 3.3.11 and 3.4.9 without Bundler, with default GC settings and YJIT disabled.
Each run uses the same library source, 320 warmup evaluations, 2,000 measured evaluations, and three alternating paired samples.
Compare implementations within each run; the MRI 4.0.9 results above use a different process environment and sample count.

| MRI | Search speedup range | Search RAM target met | Compiled workloads faster | Churn RAM target met |
| --- | ---: | ---: | ---: | ---: |
| 3.3.11 | 1.14x to 61.58x | 14 of 18 | 7 of 18 | 15 of 18 |
| 3.4.9 | 1.21x to 60.33x | 17 of 18 | 6 of 18 | 5 of 18 |

Churn is faster in all 18 workloads on both versions.
Raw results include every mode and sample: [MRI 3.3.11](../../benchmark/results/mri-3.3.11-defaults.json) and [MRI 3.4.9](../../benchmark/results/mri-3.4.9-defaults.json).
Repeat either run with its installed Ruby interpreter:

```sh
ruby script/benchmark.rb --ruby-root /path/to/jmespath.rb --iterations 2000 --rounds 3 --memory --output /tmp/jmespath-defaults.json
```

A separate projection diagnostic uses 640 warmup evaluations, 20,000 measured searches, and three paired samples without Bundler.
The table reports median peak RAM and collections during the measured loop.

| MRI | Search speedup | Peak RAM, library / reference (MiB) | GC collections, library / reference |
| --- | ---: | ---: | ---: |
| 3.3.11 | 1.72x | 19.28 / 18.36 | 12 / 173 |
| 3.4.9 | 1.70x | 20.97 / 19.50 | 8 / 95 |
| 4.0.9 | 1.61x | 22.44 / 21.14 | 10 / 96 |

Retained Ruby object bytes are lower in all three diagnostic runs, while peak RAM is 5% to 8% higher.
Native snapshots on MRI 4.0.9 show array memory returning to baseline after full GC, while about 1 MiB of extra physical footprint remains.
This supports temporary array accumulation and native allocator retention as causes of the gap in that workload.

Three isolated alternatives failed to meet both targets.
Growing projection arrays incrementally leaves peak RAM 7% to 9% higher and reduces speed.
An eight-entry cache leaves peak RAM 14% higher in the deep-query churn case on MRI 3.4.9.
Uncached public search makes the projection case 5% slower than the reference, with peak RAM 0.4% higher.
These experimental alternatives were not adopted.
The [diagnostic report](../../benchmark/results/default-gc-diagnosis.json) preserves raw samples, source fingerprints, and native memory snapshots.

## Optimization decisions

Default searches reuse immutable configuration and compiled operations.
Field readers share the data-access implementation.
Slices prepare their bounds and direction once per compiled expression.
Native string length and reversal bypass generic function dispatch.
Function arguments and expression-reference callbacks use compiled operations; function signatures remain checked.
Operations without a compiled handler use the evaluator.
Compiled expressions can save a custom registry and error policy while retaining compiled operations.
Field dispatch avoids the generic handler lookup.
Projections compact a single result array, and stable sorting uses one key-and-index pair per item.
Whitespace runs are scanned together.
The cache retains 32 expressions, with the existing 1,048,576-byte source limit.

An experimental cache removed default-hit allocations but increased peak RAM by 32% in a 20,000-search projection comparison.
That variant was rejected.
Ruby's garbage-collection schedule can make fewer allocations coexist with higher peak RAM; compare both metrics on representative workloads.
