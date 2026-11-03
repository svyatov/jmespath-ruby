# jmespath-ruby

Search JSON and Ruby data with reusable queries and typed custom functions.

- Runs on Ruby 3.3 and later with a pure Ruby implementation.
- Replaces [jmespath.rb](https://github.com/jmespath/jmespath.rb)'s documented `JMESPath.search` API; see the [migration limits](#replace-jmespathrb).
- Reuses compiled queries and supports typed custom functions.

## Install

In your Ruby project, add the gem with Bundler. Run `bundle init` first if the project has no Gemfile.

```sh
bundle add jmespath-ruby --version "~> 0.1.3"
```

Save this Ruby example as `example.rb`:

```ruby
require "jmespath"

data = {user: {name: "Ada"}}
JMESPath.search("user.name", data) #=> "Ada"
```

Run it with `bundle exec ruby example.rb`. The final expression returns `"Ada"`.

## Common tasks

| Task | Example | Reference |
| --- | --- | --- |
| Search Ruby data | [Search](#search) | [Search semantics](docs/guides/search.md) |
| Reuse a query | [Compile once](#compile-once) | [Compilation](docs/guides/compilation.md) |
| Require a non-null result | [Required results](#required-results) | [Result rules](docs/guides/compilation.md#required-results) |
| Handle an evaluation failure | [Failure results](#failure-results) | [Failure ownership](docs/guides/errors.md#failure-results) |
| Debug an unexpected result | [Trace and inspect](#debug-a-query) | [Tracing](docs/guides/compilation.md#evaluation-tracing) and [inspection](docs/guides/compilation.md#query-inspection) |
| Search a JSON file from the shell | [Command line](#command-line) | [Command-line reference](docs/guides/command-line.md) |

## Replace jmespath.rb

The official jmespath.rb project publishes the gem named `jmespath`.
Replace that Gemfile entry:

```diff
-gem "jmespath"
+gem "jmespath-ruby", "~> 0.1.3"
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

See [search semantics](docs/guides/search.md) for inputs, filters, and projections.

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

See [compilation](docs/guides/compilation.md) for saved options, caching, and threading.

## Required results

Use `Expression#fetch` when a Ruby caller requires a non-null result:

```ruby
JMESPath.compile("user.name").fetch({user: {name: "Ada"}}) #=> "Ada"
```

Null results raise `JMESPath::Errors::NullResultError`, whose `expression` attribute contains the query text.
False, zero, and empty values succeed.
See [required query results](docs/guides/compilation.md#required-results) for options and suppression behavior.

## Failure results

Use `Expression#try_search` in Ruby code to distinguish a successful null result from a library-owned failure:

```ruby
query = JMESPath.compile("length(@)")
query.try_search("Ada").value #=> 3
query.try_search(4).success? #=> false
query.try_search(4).error.function_name #=> "length"
JMESPath.compile("missing").try_search({}).success? #=> true
```

The frozen `JMESPath::SearchResult` exposes `success?`, `value`, and the original `error`.
Library-owned evaluation, JSON parsing, and native input I/O failures become failure results.
Invalid options and exceptions from application callbacks or conversions still raise.
Compilation can raise syntax errors before `try_search` runs.
See [failure results](docs/guides/errors.md#failure-results) for ownership and suppression rules.

## Debug a query

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

## Command line

Both `jmespath` and `jmespath.rb` search JSON from a file or stdin:

```sh
jmespath --file document.json 'user.name'
```

For a document containing `{"user":{"name":"Ada"}}`, stdout contains `"Ada"` and a newline.
See the [command-line reference](docs/guides/command-line.md) for query files, output modes, validation, and interactive sessions.
Use [shell completion](docs/guides/completion.md) for Bash and Zsh setup.

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

## Performance

Measured public search is 7.97x faster than jmespath 1.6.2 by geometric mean on MRI 4.0.9 across 18 matching workloads.
Query reuse has different results across implementations and runtimes.
See the [full comparison](docs/guides/comparison.md) for exact versions, workload results, and methodology.
See [performance measurements](docs/guides/performance.md) for cache, startup, and memory experiments.

## Why choose jmespath-ruby?

- **Reuse work across searches.** Compile once, save query options, and share immutable expressions across threads.
- **Add functions without global patches.** Typed, immutable registries validate arguments before your callback runs.
- **Type-check integrations.** The gem ships RBS signatures for its public API.
- **Use Ruby data directly.** Search string-keyed or symbol-keyed hashes, Structs, arrays, JSON streams, and Pathname inputs.
- **Control query growth.** The synchronized cache holds at most 32 queries and 1 MiB of source text; expression nesting has an explicit limit.

Both Ruby and Python upstream compliance corpora run in the test suite, alongside Ruby-specific input and error checks.
The [comparison with existing implementations](docs/guides/comparison.md) includes exact versions, rejected workloads, and reproducible measurements.

## Guides

- [Command-line reference](docs/guides/command-line.md)
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
