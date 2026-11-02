# Changelog

All notable changes are recorded here using [Keep a Changelog 2.0.0](https://keepachangelog.com/en/2.0.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) for the public contract defined in [VERSIONING.md](VERSIONING.md).

## [Unreleased]

### Added

- Add `JMESPath.validate` with immutable syntax diagnostics and configurable nesting limits.
- Add `--validate EXPRESSION` to both executables for syntax validation without reading standard input.

## [0.1.2] - 2026-11-02

### Added

- Add `JMESPath::Diagnostic.format` for syntax reasons, source coordinates, query excerpts, and carets.
- Expose immutable function validation data, including argument positions, expected and actual types, arity, and query byte ranges.
- Add `Functions#names`, `Functions#metadata`, and optional custom function descriptions for immutable registry inspection.
- Suggest similar names from the active registry for unknown functions; expose the missing name and ranked suggestions on the error.

### Changed

- Show located CLI syntax, function type, and arity diagnostics; describe validation and suggestions in CLI help.
- Report malformed CLI input as `Invalid JSON input` without exposing JSON parser messages or document fragments.

## [0.1.1] - 2026-11-01

### Changed

- Expand installation, support, contribution, and performance comparison documentation.
- Publish gems with build provenance, a dependency inventory, and attested release assets.

## [0.1.0] - 2026-11-01

Initial implementation for Ruby 3.3 and later.

### Added

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

[unreleased]: https://github.com/svyatov/jmespath-ruby/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/svyatov/jmespath-ruby/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/svyatov/jmespath-ruby/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/svyatov/jmespath-ruby/releases/tag/v0.1.0
