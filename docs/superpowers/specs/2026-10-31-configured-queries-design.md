# Configured compiled queries

Status: approved by the user on 2026-10-31.

## Intent

Configure a reusable query once, including its custom functions and error policy.
Keep all existing search and compilation calls compatible.
Reduce repeated option validation and retain compiled execution when using a custom registry.

## Evidence

The baseline is revision `f73c7e4` on MRI 4.0.9, with default GC settings and YJIT disabled.
Five alternating samples compare identical queries and documents.
The field case performs 100,000 searches per sample; other cases perform 10,000.
An extended registry adds an unused identity function, so outputs remain identical.

| Query | Default search | Extended registry | Allocations per search, default / extended |
| --- | ---: | ---: | ---: |
| Field chain | 0.0570 s | 0.1825 s | 1 / 6 |
| Projection | 0.1169 s | 0.1745 s | 2 / 7 |
| Unicode functions | 0.0061 s | 0.0337 s | 3 / 12 |

These are setup-overhead measurements, not predicted speedups for the proposed interface.
The registry currently sends the whole query through the generic evaluator, even when its added function is unused.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| Extend `JMESPath.compile` with saved options | One expression type and the established entry point | Define defaults and per-call precedence | Selected by the user |
| Add `JMESPath.prepare` and a configured query type | Separate syntax from execution configuration | Another entry point and query concept | Not selected |

## Public contract

```ruby
functions = JMESPath::Functions.default.with("double", signature: [[:number]]) { |value| value * 2 }
query = JMESPath.compile("double(price)", functions: functions, disable_visit_errors: false)
query.search({price: 12}) #=> 24
query.call({price: 15}) #=> 30
```

`compile` additionally accepts `functions:` and `disable_visit_errors:`.
They use the same validation and defaults as the existing search options.
Invalid option values fail during compilation, before any document is evaluated.

`Expression#search` uses saved options when callers omit them.
Explicit per-call options override saved defaults for that call only.
Unspecified options retain their saved values.
Conflicting positional and keyword values continue to raise `ArgumentError`.
Existing unconfigured expressions retain their existing behavior.

`Expression#call` is an alias for `search`, with identical inputs, options, and results.
It provides Ruby's callable interface without a second evaluation contract.

## Implementation constraints

Compiled expressions and registries remain immutable and shareable between threads.
The global cache continues to retain only unconfigured syntax, never custom registries or input data.
A configured expression may reuse cached syntax while owning its evaluation configuration and compiled plan.
Per-call overrides neither mutate the expression nor enter the global cache.

Compile supported operations against the selected registry and error policy.
Custom registries must honor overrides of built-in functions.
Unsupported operations may use an evaluator configured once for that expression.
Unknown functions continue to fail during evaluation, not compilation.
Argument order, validation, fresh expression references, and literal ownership remain unchanged.
Suppressed validation failures must not hide adapter errors or nested callback failures.

The implementation remains pure Ruby and uses default GC settings on MRI 3.3, 3.4, and 4.0.
No dependencies, batch interface, CLI changes, or query-language extensions are included.
Compiling additional node kinds is separate work and is outside this increment.

## Verification

Test the contract through `JMESPath.compile`, `Expression#search`, and `Expression#call`.
Cover saved defaults, partial overrides, invalid options, cache isolation, concurrency, adapters, and callback error provenance.
Run the existing compliance suite, public signatures, documentation examples, lint, coverage, and complexity checks.
Compare configured reuse with the equivalent existing per-call options on all three supported MRI series.
Retain an optimization only when repeated samples show a gain and correctness checks agree.
Recheck default searches to detect regressions.
