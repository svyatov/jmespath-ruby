# jmespath-ruby

A pure Ruby implementation of JMESPath for Ruby 3.3 and later.

Search JSON-compatible values, compile expressions for reuse, and register typed custom functions.
The package keeps `require "jmespath"` and `JMESPath.search` while using the gem name `jmespath-ruby`.

## Install from this checkout

```sh
bundle install
bundle exec rake build
gem install ./pkg/jmespath-ruby-0.1.0.gem
```

For a local Bundler application:

```ruby
gem "jmespath-ruby", path: "/path/to/jmespath-ruby"
```

Use one provider per bundle.
A dependency on the package named `jmespath` needs its own dependency change; this gem cannot satisfy that name automatically.

## Search

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

```ruby
expression = JMESPath.compile("user.name")
expression.search({user: {name: "Ada"}}) #=> "Ada"
expression.search({user: {name: "Lin"}}) #=> "Lin"
```

Compiled expressions are immutable and safe to share between threads.
Each search uses separate evaluation state.
Custom callbacks and input objects remain the caller's responsibility.

## Custom functions

```ruby
functions = JMESPath::Functions.default.with("double", signature: [[:number]]) { |number| number * 2 }
JMESPath.search("double(price)", {price: 12}, functions: functions) #=> 24
```

Registration returns a separate immutable registry.
An existing function requires `override: true` to replace it.
Every argument, including variadic arguments, is validated before the callback runs.

## Command line

Both `jmespath` and `jmespath.rb` accept an expression and a JSON document on standard input.

```sh
printf '%s\n' '{"user":{"name":"Ada"}}' | jmespath 'user.name'
```

The result goes to standard output as JSON.
Errors go to standard error with a nonzero status.

## Guides

- [Search semantics](docs/guides/search.md)
- [Compilation, caching, and threading](docs/guides/compilation.md)
- [Built-in and custom functions](docs/guides/functions.md)
- [Errors and limits](docs/guides/errors.md)
- [Compatibility and migration](docs/guides/compatibility.md)
- [Performance measurements](docs/guides/performance.md)
- [Development](CONTRIBUTING.md)

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
