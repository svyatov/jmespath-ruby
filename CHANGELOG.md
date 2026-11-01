# Changelog

## 0.1.0 - 2026-11-01

Initial implementation for Ruby 3.3 and later.

- Implement the JMESPath language and all 26 standard functions.
- Preserve the public `require "jmespath"` and `JMESPath.search` entry points under the `jmespath-ruby` package name.
- Add immutable compiled expressions, bounded synchronized caching, and immutable custom function registries.
- Save custom function registries and error-handling defaults in compiled expressions; expose `Expression#call` as an alias for `search`.
- Compile common evaluation operations and reduce repeated allocation, field lookup, and function-validation costs.
- Support Ruby hashes, symbol keys, Struct values, explicit conversion protocols, streams, and paths.
- Include both command-line executable names, public RBS signatures, and executable YARD examples.
- Validate pinned Python and Ruby compliance fixtures, declared compatibility corrections, and production-only gem installation.
- Include reproducible speed and process-memory comparisons across MRI 3.3, 3.4, and 4.0 with default GC settings.

The compatibility guide documents intentional corrections and limits.
Applications that depend on the gem name `jmespath` must change that dependency explicitly.
