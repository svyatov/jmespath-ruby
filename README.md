# jmespath-ruby

Search JSON and Ruby data with reusable queries and typed custom functions.

- Runs on Ruby 3.3 and later with a pure Ruby implementation.
- Replaces [jmespath.rb](https://github.com/jmespath/jmespath.rb)'s documented `JMESPath.search` API; see the [migration limits](#replace-jmespathrb).
- Reuses compiled queries and supports typed custom functions.
- Measured 7.97x geometric-mean public-search speedup over jmespath 1.6.2 on MRI 4.0.9; see the [benchmark results](docs/guides/comparison.md).

## Install

In your Ruby project, add the gem with Bundler. Run `bundle init` first if the project has no Gemfile.

```sh
bundle add jmespath-ruby --version "~> 0.1.2"
```

Save this Ruby example as `example.rb`:

```ruby
require "jmespath"

data = {user: {name: "Ada"}}
JMESPath.search("user.name", data) #=> "Ada"
```

Run it with `bundle exec ruby example.rb`. The final expression returns `"Ada"`.

## Performance

**Fastest public search in every matching MRI benchmark case.**
On MRI 4.0.9, jmespath-ruby beats each competing implementation on every workload that both return correctly.

| Implementation | Version | Correct workloads | jmespath-ruby public-search speedup |
| --- | --- | ---: | ---: |
| **jmespath-ruby** | **0.1.0** | **18/18** | **Baseline** |
| jmespath (jmespath.rb) | 1.6.2 | 18/18 | **7.97x** |
| BurtPath | 1.1.2 | 15/18 | **9.99x** |
| Jamespath | 0.5.1 | 13/18 | **8.07x** |

Speedups use geometric means of median times across each competitor's correctly evaluated workloads.
Measurements use five rounds of 20,000 searches on an Apple M1 Pro.
The suite includes all 12 upstream benchmark cases and six supplemental cases.
Results vary by workload: **1.35x to 78.48x faster than jmespath 1.6.2** in this run.

Query reuse has different results: BurtPath's private cached runtime is faster in five workloads, and Jamespath has three lower medians.
The [full comparison](docs/guides/comparison.md) includes those results, JRuby, failures, methodology, and raw samples.
The JRuby-only `jmespath-jruby` 1.0.0.pre0 fails on the tested JRuby 10.1 runtime; its results are recorded separately.

## Why choose jmespath-ruby?

- **Reuse work across searches.** Compile once, save query options, and share immutable expressions across threads.
- **Add functions without global patches.** Typed, immutable registries validate arguments before your callback runs.
- **Type-check integrations.** The gem ships RBS signatures for its public API.
- **Use Ruby data directly.** Search string-keyed or symbol-keyed hashes, Structs, arrays, JSON streams, and Pathname inputs.
- **Control query growth.** The synchronized cache holds at most 32 queries and 1 MiB of source text; expression nesting has an explicit limit.

Both Ruby and Python upstream compliance corpora run in the test suite, alongside Ruby-specific input and error checks.
The [comparison with existing implementations](docs/guides/comparison.md) includes exact versions, rejected workloads, and reproducible measurements.

| Feature | jmespath-ruby | jmespath | BurtPath | Jamespath | jmespath-jruby |
| --- | --- | --- | --- | --- | --- |
| Public query compilation | Yes | No | No | Yes | Yes |
| Documented typed function registry | Yes | No | No | No | No |
| Packaged RBS signatures | Yes | No | No | No | No |
| Pure Ruby implementation | Yes | Yes | Yes | Yes | No |
| Ordinary `JMESPath.search` calls | Yes | Yes | Yes | No | No |

`jmespath` and BurtPath support reuse through private runtime classes.
The [full comparison](docs/guides/comparison.md) distinguishes those classes from public compilation APIs.

## Replace jmespath.rb

The official jmespath.rb project publishes the gem named `jmespath`.
Replace that Gemfile entry:

```diff
-gem "jmespath"
+gem "jmespath-ruby", "~> 0.1.2"
```

Run `bundle install`. Your Ruby code keeps the same entry points:

```ruby
require "jmespath"
JMESPath.search("user.name", {user: {name: "Ada"}}) #=> "Ada"
```

Use one provider per bundle.
A third-party dependency that requires the package named `jmespath` needs a dependency change; Bundler cannot substitute `jmespath-ruby` automatically.
Private parser/runtime classes and exact error messages are outside the replacement contract.
Validation is stricter for invalid function arguments, and empty `min_by`/`max_by` results return nil.
See [compatibility and deliberate corrections](docs/guides/compatibility.md) before migrating.

## Search

Use `Expression#fetch` when a Ruby caller requires a non-null result:

```ruby
JMESPath.compile("user.name").fetch({user: {name: "Ada"}}) #=> "Ada"
```

Null results raise `JMESPath::Errors::NullResultError`, whose `expression` attribute contains the query text.
False, zero, and empty values succeed.
See [required query results](docs/guides/compilation.md#required-results) for options and suppression behavior.

Use `JMESPath.search` in Ruby code to evaluate a query:

```ruby
require "jmespath"

data = {people: [{name: "Ada", active: true}, {name: "Lin", active: false}]}
JMESPath.search("people[?active].name", data) #=> ["Ada"]
JMESPath.search("people[*].name", data) #=> ["Ada", "Lin"]
JMESPath.search("missing", data) #=> nil
```

Missing fields return nil.
Projections omit nil results and retain false values.
The library preserves selected input objects and does not mutate the input.

## Compile once

Use `JMESPath.compile` in Ruby code to reuse a parsed expression:

```ruby
expression = JMESPath.compile("user.name")
expression.search({user: {name: "Ada"}}) #=> "Ada"
expression.search({user: {name: "Lin"}}) #=> "Lin"
```

Compiled expressions are immutable and safe to share between threads.
Each search uses separate evaluation state.
Custom callbacks and input objects remain the caller's responsibility.

In Ruby code, inspect the query without evaluating input or resolving function names:

```ruby
JMESPath.compile("user.name").explain[:root][:operation] #=> "subexpression"
```

See [query inspection](docs/guides/compilation.md#query-inspection) for the immutable tree format, operation IDs, and source ranges.

In Ruby code, trace omissions during one evaluation with a bounded event limit:

```ruby
query = JMESPath.compile("items[*].name")
report = query.trace({items: [{name: "Ada"}, {}, {name: false}]}, limit: 100)
report[:value] #=> ["Ada", false]
report[:events].map { |event| event[:type] } #=> ["field_null", "projection_omission"]
```

See [evaluation tracing](docs/guides/compilation.md#evaluation-tracing) for event types, local item indexes, and truncation.

In Ruby code, save evaluation options when compiling a query, then use `search` or its `call` alias:

```ruby
query = JMESPath.compile("length(name)", disable_visit_errors: true)
query.call({name: "Ada"}) #=> 3
query.call({name: nil}) #=> nil
```

## Custom functions

Create a function registry in Ruby code and pass it to `JMESPath.search`:

```ruby
functions = JMESPath::Functions.default.with("double", signature: [[:number]]) { |number| number * 2 }
JMESPath.search("double(price)", {price: 12}, functions: functions) #=> 24
```

Registration returns a separate immutable registry.
An existing function requires `override: true` to replace it.
Every argument, including variadic arguments, is validated before the callback runs.

Inspect registered functions in Ruby without executing their callbacks:

```ruby
JMESPath::Functions.default.names.include?("length") #=> true
metadata = JMESPath::Functions.default.metadata("length")
metadata.signature #=> [[:string, :array, :object]]
metadata.description #=> "Character or element count."
```

Use `description:` when registering a custom function to include its description in immutable metadata.
See [registry inspection](docs/guides/functions.md#registry-inspection) for all fields and override behavior.

## Errors and diagnostics

Format syntax failures in Ruby with `JMESPath::Diagnostic.format(error)` to get source coordinates, a query excerpt, and a caret.
Function type and arity errors expose immutable validation data, including the function name, signature, argument counts or types, and available source ranges.
Unknown-function errors expose the missing name and up to three suggestions from the active registry.
See [errors and diagnostics](docs/guides/errors.md) for examples, nullable fields, and source-location limits.

## Command line

Both `jmespath` and `jmespath.rb` accept an expression and a JSON document from stdin or `--file PATH`.
Use `--query-file PATH` to read the expression from a UTF-8 file.

```sh
printf '%s\n' '{"user":{"name":"Ada"}}' | jmespath 'user.name'
jmespath --file document.json 'user.name'
jmespath 'user.name' --file document.json
jmespath --file 'my document.json' 'user.name'
jmespath --file=--document.json 'user.name'
jmespath --file ./--document.json 'user.name'
jmespath --file - 'user.name'
jmespath --file document.json -- 'user.name'
jmespath --query-file query.jmespath < document.json
jmespath --query-file query.jmespath --file document.json
jmespath --pretty 'items' < document.json
jmespath --raw-output 'user.name' < document.json
```

Document files are read as UTF-8 and closed after parsing, before query evaluation in single-document mode.
File input leaves stdin unused; omitting `--file` selects stdin.
Paths are literal: `--file -` reads a file named `-`.
Quote filenames with spaces; use the equals form or `./` prefix for option-like filenames.
Options can precede or follow the expression; `--` ends option parsing.
Supply exactly one query source: a positional expression or `--query-file PATH`.
Repeated file options, unknown options, missing values, and conflicting or absent query sources are usage failures.
Help and version flags must appear alone.

List built-in functions from the shell without reading stdin:

```sh
jmespath --functions
```

Each line shows a name, accepted argument types, and the description from public function metadata.
The listing is alphabetical and ends with a notation legend.
Unions use `|`, homogeneous arrays use `array<T>`, and expression references use `expref`.
A final `...` means the last argument repeats and remains required.
Runtime checks can be narrower than the declared types.
See [the function listing](docs/guides/functions.md#command-line-reference) for examples.

Use `--functions` alone; queries, paths, other modes, repeated flags, and values are usage failures.
The two-argument form `--validate --functions` retains literal query validation.
Listing exits with status 0 on success, 1 for output failures, or 2 for usage failures.
Usage failures leave stdout empty and print usage guidance on stderr.

Query files retain all source text, including trailing newlines and Unicode diagnostic coordinates.
An empty query file produces a syntax failure.
Query files close after reading, before document input is accessed.
Missing or unreadable query files leave document input untouched.
In single-document mode, execution parses JSON before compiling the expression.
Query paths follow the document path rules: `--query-file -` reads a literal file named `-`.

The result goes to standard output as compact JSON followed by a newline.
Use `--pretty` for JSON with two-space indentation and one final newline.
Both formats support objects, arrays, strings, numbers, booleans, and null, with Unicode preserved.
Pretty output works with positional or file queries and either document source.
Repeated `--pretty` options are usage failures.
Pretty formatting preserves stderr diagnostics, source coordinates, and exit statuses; failures before output starts leave stdout empty.
Use `--raw-output` to print string results without JSON quotes or escape encoding.
Other result types retain compact JSON encoding.
Raw output appends one newline and preserves every embedded and trailing newline in the result.
An empty string produces one newline; a string ending with one newline produces two.
Repeated `--raw-output` options and combinations with `--pretty` are usage failures.
Raw output preserves stderr diagnostics, source coordinates, and exit statuses; failures before output starts leave stdout empty.
Syntax, function type, and arity failures include source coordinates, a query excerpt, and a caret when available.
Unknown functions suggest similar registered names.
Malformed JSON input reports `Invalid JSON input` without including document fragments.
These failures go to standard error and exit with status 1.
Usage failures exit with status 2; `--help` and `--version` exit with status 0 without reading input.

Process independent JSON records with these shell commands:

```sh
jmespath --json-lines 'user.name' < events.jsonl
jmespath --json-lines --file events.jsonl --query-file query.jmespath
```

JSON Lines mode compiles the query once before opening document input or reading stdin.
Each physical line must contain one complete JSON value; blank and whitespace-only lines fail.
LF, CRLF, and a final record without a newline are accepted.
Each result is compact JSON followed by a newline, including `null` and `false`.
Empty input succeeds without output when the query is valid; an invalid query still fails.

Processing stops at the first failure with status 1 and an `Input line N:` diagnostic prefix.
Earlier results remain on stdout; check the exit status before treating output as complete.
Query compilation and file-open errors have no input line prefix.
Memory is proportional to the current record, its evaluation, and its serialized result, plus the compiled query.
Output uses normal buffering.
Owned files close after processing; caller-owned streams remain open.
Injected `CLI.run` input needs `gets` for JSON Lines or `read` for document mode; output needs only `puts`.
Repeated `--json-lines` flags and combinations with `--pretty`, `--raw-output`, or validation are usage failures.

Validate syntax without providing a JSON document by running this shell command:

```sh
jmespath --validate 'items[*].name'
jmespath --validate --query-file query.jmespath
jmespath --query-file query.jmespath --validate
```

Both executables support `--validate EXPRESSION` without reading standard input.
File validation also leaves stdin untouched and rejects document options such as `--file`.
Combining `--pretty` with validation is a usage failure, rejected before opening input files or reading stdin.
Combining `--raw-output` with validation follows the same rule.
The exact two-argument form `--validate EXPRESSION` always treats the second argument as query text, including flag-like text.
Thus `jmespath --validate --pretty` validates the literal expression `--pretty`.
Likewise, `jmespath --validate --raw-output` validates the literal expression `--raw-output`.
Valid syntax produces no output and exits with status 0.
Query failures print a diagnostic to standard error and exit with status 1; incorrect usage exits with status 2.
Validation does not check function availability or runtime argument types.
The Ruby interface is `JMESPath.validate(expression, max_depth: 128)`.
See [CLI diagnostics](docs/guides/errors.md#cli-diagnostics) for examples and fallback behavior.

## Guides

- [Search semantics](docs/guides/search.md)
- [Compilation, caching, and threading](docs/guides/compilation.md)
- [Built-in and custom functions](docs/guides/functions.md)
- [Errors and limits](docs/guides/errors.md)
- [Compatibility and migration](docs/guides/compatibility.md)
- [Performance measurements](docs/guides/performance.md)
- [Comparison with other implementations](docs/guides/comparison.md)
- [Development](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

## Help and maintenance

This project is maintained by Leonid Svyatov.
Use [GitHub issues](https://github.com/svyatov/jmespath-ruby/issues) for questions and defect reports.
Report vulnerabilities through the private channel in [SECURITY.md](SECURITY.md).

Release assets include the gem, `sbom.cdx.json`, and `SHA256SUMS`.
Verify a downloaded asset with `gh attestation verify ASSET --repo svyatov/jmespath-ruby --signer-workflow svyatov/jmespath-ruby/.github/workflows/release.yml`.
Check downloaded files against the manifest with `sha256sum -c SHA256SUMS`.

## Verify and document

```sh
bundle exec rake
bundle exec rake docs
bundle exec rake audit
```

The default task checks tests, fresh coverage, RuboCop, RBS, Steep, coverage-aware CRAP scores, and documentation.
The gates require 100% line and branch coverage, and a CRAP score at most 10 per measurable library method.
The audit task separately refreshes the dependency advisory database.
YARD output is written to `doc/index.html`.

## License

[MIT](LICENSE) for authored code.
Imported compliance fixtures retain their [upstream licenses](LICENSES/).
