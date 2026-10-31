# jmespath-ruby design

Status: proposed, awaiting user approval.

## Intent

Build a pure Ruby JMESPath implementation for Ruby 3.3 and later.
Publish it as `jmespath-ruby`, with `require "jmespath"` and `JMESPath.search` compatibility.
Use jmespath.py as a behavioral reference, supported by language compliance tests.
Provide tested documentation and enforceable quality checks.

Compatibility is a goal, subject to sound architecture and correctness.
The project must identify incompatible behavior before claiming replacement compatibility.

## Decisions and proposals

The user selected a fresh implementation with a compatibility layer, approach A1.
The user selected the package name, require path, search entry point, and Ruby 3.3 minimum.
The user requested RuboCop, crap4ruby, RSpec, and YARD documentation.
Other choices below are implementation proposals for approval through this document.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| A1: Fresh parser and evaluator with explicit compatibility adapters | Separates language behavior from Ruby integration | Requires independent compliance and compatibility evidence | Selected by the user |
| A2: Modernize jmespath.rb incrementally | Preserves more inherited behavior initially | Couples architectural changes to inherited implementation details | Not selected |

## Goals

- Implement the complete JMESPath grammar and all standard built-in functions.
- Match supported behavior in the pinned Python and Ruby references.
- Preserve documented Ruby inputs, return values, errors, and supported search options.
- Add reusable compiled expressions and explicit custom function registration.
- Support concurrent searches without shared mutable evaluation state.
- Ship public RBS signatures, checked implementation types, and validated YARD documentation.
- Make local checks reproducible through one default Rake task.

## Non-goals and anti-goals

Private classes from jmespath.rb are outside the compatibility promise.
This includes its parser, runtime, token, and node object protocols.
Custom parser injection through those private protocols is outside the initial scope.

The first release excludes native extensions, a query optimizer, streaming evaluation, and framework integrations.
Ractor support and alternative Ruby implementations require separate verification before advertising support.
Python-specific implementation objects and exception message wording are outside the compatibility promise.

Avoid whole-document conversion that breaks returned object identity.
Avoid global monkey patches, arbitrary method invocation, and Ruby evaluation of query text.
Avoid weakening quality checks or dividing coherent code solely to improve metrics.
Avoid performance claims unsupported by repeatable measurements.

## Package and compatibility boundary

The gem name is `jmespath-ruby`; the load path remains `jmespath`.
Application code can keep `require "jmespath"` and `JMESPath.search` after changing its Gemfile.

RubyGems resolves dependencies by package name.
This package cannot satisfy a declared dependency on `jmespath` automatically.
The migration guide must explain that limitation, including dependencies such as SDKs that declare `jmespath`.
Resolving those dependency declarations requires changes outside this gem.

Installing both packages introduces overlapping require paths and executable names.
Documentation must instruct users to select one provider within each application bundle.
Tests must verify the loaded provider inside an isolated bundle containing the built gem.
The project must not claim automatic replacement of transitive gem dependencies.

### Compatibility contract

Preserve `JMESPath.search(expression, data, options = {})`.
Support keyword options as an additive Ruby API.
Document precedence when positional and keyword options are combined.
Conflicting values must raise `ArgumentError` rather than depend on argument order.

Supported inputs include string-keyed and symbol-keyed hashes, arrays, scalar JSON values, and Structs.
Support Pathname, IO, and StringIO input through explicit JSON loading at the entry point.
Match upstream conversion behavior for objects implementing `to_hash`, `to_ary`, and `to_str` where applicable.
Never create symbols from query text or call arbitrary fields as methods.

Return selected objects without replacing them solely for normalization.
Construct fresh arrays and hashes when the language requires a constructed result.
Searching must not mutate the caller's data or expression string.
Input IO follows its documented read position; callers retain responsibility for closing it.

Preserve the `JMESPath::Errors` hierarchy and its named exception classes.
Keep syntax, invalid type, invalid value, invalid arity, and unknown function failures distinct.
Add structured position information for parse failures without promising identical upstream error text.

Preserve supported behavior for `cache_expressions` and `disable_visit_errors`.
Characterization tests must establish exactly which errors the latter suppresses.
Unexpected internal failures and custom function defects must propagate.

Pin legacy syntax tests, including bare backtick literals.
Treat string ordering and other accepted reference extensions as explicit compatibility behavior.
Do not infer standard behavior solely from either implementation.

### Resolving conflicting references

The language specification and compliance cases define standard behavior.
The Ruby tests define additional Ruby integration contracts.
The Python tests define additional reference features and useful edge cases.

Record each disagreement in a compatibility table with the expression, inputs, expected results, and chosen behavior.
Preserve established extensions when they do not conflict with standard behavior or correctness.
Material conflicts affecting supported applications require a user decision before implementation proceeds in that area.
Private implementation differences do not require compatibility wrappers.

The following reference defects have a proposed resolution through approval of this design:

| Reference behavior | Proposed behavior | Compatibility consequence |
| --- | --- | --- |
| Ruby `reverse` accepts surplus arguments; `to_array` omits arity validation | Enforce the standard function signatures | Invalid calls can raise errors instead of returning values |
| Ruby `min_by` and `max_by` validate a key on an empty array | Return `nil` for an empty array | Valid standard queries stop raising a type error |
| Python validates only the declared positions of variadic signatures | Validate every supplied argument | Invalid trailing arguments consistently raise the declared type error |

These cases are deliberate corrections, with regression tests and migration notes.
This limits the replacement claim to supported behavior, excluding documented reference defects.

## Public API additions

`JMESPath.compile(expression)` returns an immutable `JMESPath::Expression`.
Its `search(data, ...)` method accepts the same evaluation options and inputs as the convenience entry point.
Compilation retains an independent, frozen copy of the expression text.
Repeated evaluation does not reparse the expression.

Custom functions use an explicit registry with declared argument signatures.
Registry construction returns independent definitions; evaluation receives an immutable registry.
Built-in and custom functions share arity and type validation.
Replacing a built-in requires explicit intent, rather than accidental name collision.

Support expression references, typed arrays, union argument types, and variadic arguments.
Validate every variadic argument.
Custom function exceptions retain their original class and backtrace.
Callbacks must follow documented thread-safety and mutation requirements.
The exact registration syntax is left to the builder, with examples and RBS signatures required before stabilization.

## Architecture

Use a lexer, a Pratt parser, immutable syntax nodes, and a tree evaluator.
The parser owns precedence, projection boundaries, and syntax errors.
The evaluator owns language semantics and delegates data access to explicit adapters.
The function registry owns lookup, signatures, arity, and argument validation.

Keep parsing independent of evaluation options and input representation.
Keep JSON loading outside the parser and evaluator.
Keep function validation outside parsing.
Choose node classes and dispatch granularity based on cohesive behavior, measured complexity, and readable types.

### Data access

Use one data-access boundary for field lookup, object values, array access, and supported conversions.
Prefer direct operations for plain Ruby JSON structures.
Use explicit adapters for Structs and implicit-conversion objects.
Do not recursively copy the entire input to implement compatibility.

Centralize JMESPath truthiness, type classification, and structural equality.
Ruby truthiness does not implement JMESPath truthiness.
Equality must preserve the language's number, boolean, array, and object rules.
Built-in functions must use the same type model as operators.

### Immutable compilation and caching

Compiled syntax, literal templates, and registry definitions must be immutable.
Evaluation state belongs to one search call.
Mutable literal results must not leak changes between searches.
Returning caller-owned values does not make those values immutable.

Use a bounded, synchronized compilation cache for convenience searches.
Bound both entry count and retained source bytes.
Oversized expressions can bypass caching without becoming invalid queries.
Cache keys must not depend on mutable caller-owned strings.
Cache only syntax, never input data, registries, or search results.
Disabling caching must preserve evaluation behavior.

### Limits and diagnostics

Reject invalid encodings and malformed query text with useful syntax errors.
Detect excessive parser nesting before Ruby raises `SystemStackError`.
Expose a documented configurable nesting limit, independent of cache limits.
The builder selects a conservative default and records its compatibility effect.

Exercise wide queries, deep queries, long Unicode strings, malformed escapes, and repeated cache misses.
Document that function callbacks and caller-owned input can perform arbitrary work.
The library does not promise evaluation timeouts or a security sandbox.

## Command-line interface

Provide `jmespath` and the compatible `jmespath.rb` executable name.
Accept an expression argument and a JSON document on standard input.
Write one JSON result to standard output.
Write usage and evaluation failures to standard error with a nonzero exit status.
Include help and version output.
The first release excludes an interactive shell and additional input formats.

## Testing and reference evidence

Use RSpec for unit, integration, compatibility, documentation, and installed-gem tests.
Randomize example order and print the seed.
Test public behavior and invariants, including error paths and concurrency.

Vendor compliance fixtures from pinned upstream commits, with source records and required license notices.
Keep upstream fixtures separate from project-specific regression cases.
Normal tests must run without network access or a Python runtime.

The implementation plan must inventory every fixture file and supported Ruby compatibility behavior.
Every skipped or adjusted upstream case needs a recorded reason.
Syntax tests must check error classes and locations, not merely that something raises.

Run Python and legacy Ruby comparisons in isolated processes during development.
Compare JSON-representable inputs, semantic outputs, and normalized error categories.
Use separate Ruby processes to prevent overlapping require paths from contaminating results.
Review generated cases for validity before treating differences as defects.

Test string/symbol key collisions, false and nil values, conversion protocols, and selected object identity.
Test negative slices, Unicode, null omission, stable ordering, short-circuiting, and variadic validation.
Test repeated evaluation after callers mutate earlier literal results.
Test cache eviction, disabled caching, and concurrent compilation and evaluation.
Test custom function failures without broad exception suppression.

## Quality tooling and gates

Use upstream-documented packages and installation instructions.
Verify supported releases and Ruby requirements when dependencies are selected.
Keep development tools outside runtime dependencies.
Declare standard-library gem dependencies when required by supported Ruby packaging.

| Tool | Purpose | Required gate |
| --- | --- | --- |
| RSpec | Behavioral, compliance, compatibility, and packaging tests | All examples pass |
| SimpleCov | Fresh line and branch coverage for library code | 100% lines and at least 95% branches |
| RuboCop | Ruby 3.3 syntax, correctness, style, and complexity checks | No offenses or generated exclusion baseline |
| crap4ruby | Coverage-aware Change Risk Anti-Patterns score | Every measurable library method scores at most 10 |
| RBS and Steep | Public signatures and implementation type checks | Valid signatures and no type errors |
| YARD | API references and documentation integrity | Full public API coverage and no unresolved links or warnings |
| bundler-audit | Dependency advisory checks | No unaddressed reported vulnerability |
| Rake | Shared local and CI task orchestration | Default task runs the deterministic quality suite |

Start SimpleCov before loading library code.
Include unloaded library files in coverage.
Generate coverage for the exact source revision being analyzed.
Feed that resultset to crap4ruby after the test suite.
Use `--no-save` for checks that should not create tracked metric snapshots.
Complexity-only analysis must never be reported as measured CRAP.
Report unmeasurable methods explicitly and review them before release.

Keep dynamic Ruby integration types at explicit boundaries.
Internal syntax and evaluator contracts need meaningful types, rather than blanket `untyped` signatures.
Use project-wide checks for library code and public interfaces.
An exception needs a narrow scope, a reason, and review.

Advisory database updates need network access and a separate, explicit Rake task.
CI runs that task alongside the deterministic suite.
Do not require extra lint plugins unless their checks add useful coverage beyond the selected tools.

## Documentation

YARD covers every public class, module, method, option, error, and extension point.
Document parameter types, return types, mutation, thread safety, and ownership where applicable.
Explain projection versus flattening, missing values, truthiness, and expression references with tested examples.
Mark internal implementation surfaces as private.

The guide set covers installation, migration, search, compilation, functions, errors, performance, and development.
Include a compatibility table with explicit package and transitive-dependency limits.
Explain string and symbol key handling, implicit conversions, IO reads, and nesting limits.

Execute public examples against the library through RSpec-backed documentation checks.
Avoid a second, independently maintained copy of examples in tests.
Validate links and YARD tags through repository tasks.
Fail documentation checks on undocumented public methods and malformed references.
Generate browsable HTML documentation as a CI artifact.

## Performance evidence

Benchmark one-shot search, repeated convenience search, and compiled expression reuse separately.
Include field traversal, projections, filters, sorting, slicing, Unicode, and cache churn.
Measure elapsed time and object allocations on identical workloads.
Record Ruby version, platform, JIT configuration, fixture hashes, and upstream versions.
Separate startup costs from repeated evaluation.

Compare against pinned jmespath.rb using alternating runs and adequate warmup.
Verify identical expected results before comparing timings.
Explain material regressions and address avoidable causes before calling the package a replacement.
Set no speed claim or arbitrary wall-clock CI threshold before measurement.

## CI, packaging, and delivery

Test MRI Ruby 3.3, 3.4, and 4.0 on Linux.
Run a macOS packaging and CLI smoke test.
Use Ruby 3.3 as the syntax floor for development tools.
Select tool versions that support the complete required matrix.

Build the gem and inspect its file manifest.
Install it in an isolated environment without development dependencies.
Verify its require path, API, executables, packaged signatures, and documentation files.
Exclude coverage, generated documentation, local caches, and development secrets from the gem.

The proposed initial version is 0.1.0.
Use Semantic Versioning and document the public compatibility surface.
Dropping Ruby 3.3 support requires a major release after 1.0.

Prepare release tasks and documentation during implementation.
Remote repository creation, publication, and hosting configuration require a separate user request.
The implementation is complete only when required local checks pass and remaining external checks are identified.

## Provenance and licenses

Use MIT for authored code, subject to approval of this design.
Preserve upstream license terms and attribution for imported fixtures or other copied material.
jmespath.py uses MIT; jmespath.rb uses Apache-2.0.
Verify the license of each imported path before copying it.
Keep a source manifest with repository, commit, imported paths, and local changes.

Reference snapshots inspected for this design:

- [jmespath.py, commit 2812594](https://github.com/jmespath/jmespath.py/tree/2812594e69d43098ef60f81f4efc404c071b0418).
- [jmespath.rb, commit 5e86ea7](https://github.com/jmespath/jmespath.rb/tree/5e86ea7da2e954cc12f5b3a8383a43c0a65acba7).
- [JMESPath language specification](https://jmespath.org/specification.html).

## Builder choices and approval boundary

The builder chooses file layout, node representation, registry syntax, tool versions, and narrow task implementation details.
The builder also selects cache capacities and a documented nesting default, supported by tests and benchmarks.
The implementation plan must make these choices concrete before their corresponding code is written.

This document proposes full language support, custom functions, CLI compatibility, RBS/Steep, quality thresholds, and MIT licensing.
Those proposals become requirements only when the user approves this document.
Implementation starts after design approval and completion of the implementation plan.
