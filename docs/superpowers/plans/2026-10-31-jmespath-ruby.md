# jmespath-ruby implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved Ruby 3.3+ JMESPath gem with tested compatibility, checked types, and executable API documentation.

**Architecture:** A byte-oriented lexer feeds a Pratt parser that produces immutable syntax nodes. A tree evaluator uses explicit Ruby data adapters and an immutable function registry. Public search and compilation share bounded caching and per-call evaluation state.

**Tech Stack:** Ruby, JSON, StringIO, RSpec, SimpleCov, RuboCop, crap4ruby, RBS, Steep, YARD, bundler-audit, and Rake.

**Spec:** [Approved design](../specs/2026-10-31-jmespath-ruby-design.md). Read both documents before implementing a task.

## Global constraints

- Build a pure Ruby JMESPath implementation for Ruby 3.3 and later.
- Publish it as `jmespath-ruby`, with `require "jmespath"` and `JMESPath.search` compatibility.
- The initial version is 0.1.0.
- Use MIT for authored code.
- Test MRI Ruby 3.3, 3.4, and 4.0 on Linux.
- Run a macOS packaging and CLI smoke test.
- Normal tests must run without network access or a Python runtime.
- Private classes from jmespath.rb are outside the compatibility promise.
- Custom parser injection through those private protocols is outside the initial scope.
- Searching must not mutate the caller's data or expression string.
- Unexpected internal failures and custom function defects must propagate.
- SimpleCov: 100% lines and at least 95% branches.
- crap4ruby: Every measurable library method scores at most 10.
- RBS and Steep: Valid signatures and no type errors.
- YARD: Full public API coverage and no unresolved links or warnings.
- RuboCop: No offenses or generated exclusion baseline.
- Remote repository creation, publication, and hosting configuration require a separate user request.

Use the dependency-vetting skill before installing dependencies. Use atomic commits and test-driven development during implementation.
Create an isolated feature worktree through the worktree skill when execution starts; preserve the approved documents.
The tasks below form one dependent library project, rather than separate deployable subsystems.

Use `bundle exec rubocop` for lint checks, `bundle exec rbs -I sig validate` for signatures, and `bundle exec steep check` for implementation types.
Each command must exit 0; no lint offenses, invalid signatures, or type errors are accepted.
After Task 12, use `bundle exec rake` for the complete deterministic gate.

## Review focus

- R1: A cyclic Ruby container must not crash structural equality or JSON conversion with uncontrolled recursion.
- R2: Custom callbacks raising library exception classes must propagate even when visit errors are disabled.
- R3: A false string-key value wins over a symbol key; a nil string-key value follows the pinned Ruby fallback.
- R4: Mutating expression text or a previous literal result must not change cached evaluation.
- R5: Unicode positions, nested expressions, and long flat chains must produce stable results or explicit limit errors.

R1 belongs to Tasks 2 and 8; R2 belongs to Tasks 4 and 9.
R3 belongs to Task 2; R4 belongs to Tasks 5 and 9.
R5 belongs to Tasks 1, 3, and 6.

## Decisions made for implementation

Use Ruby 3.3 syntax, double-quoted strings, frozen string literals, and immutable internal records.
Use byte offsets in tokens and syntax errors; expose one-based line and character column separately.
Transcode valid expression strings into a private UTF-8 copy; reject invalid encodings through `Errors::SyntaxError`.

Set `max_depth` to 128 by default, with accepted values from 1 through 128.
This is a nesting limit, not a query length or input-document depth limit.
Flatten sequential syntax internally so long field chains and pipes do not consume recursive evaluation frames.
Explain the bound in migration documentation and verify its ceiling on every supported MRI version.

Set the shared cache to 256 entries and 1,048,576 retained source bytes.
Use synchronized least-recently-used eviction, with parsing outside the cache lock.
Do not cache expressions larger than the source-byte budget.
Key compilation by the private source copy and parser-affecting options.
Concurrent duplicate misses may parse twice; they must produce equivalent immutable results.

Accept these search options: `cache_expressions`, `disable_visit_errors`, `functions`, and `max_depth`.
Reject unknown keys, invalid option types, and conflicting positional/keyword values with `ArgumentError`.
Equal duplicate values are accepted.
`disable_visit_errors` suppresses library-generated invalid-type and invalid-arity failures only.
Syntax, invalid-value, unknown-function, adapter failures, and callback failures still raise.

### Shared interfaces

The `value` type means JSON values plus the supported Struct and implicit-conversion boundaries.
Use recursive RBS JSON aliases internally; restrict `untyped` to those dynamic integration boundaries.

| Interface | Contract |
| --- | --- |
| `Lexer.new(source, max_depth: 128).tokens` | Returns frozen Token records with `type`, `value`, `start`, and `finish`, including EOF |
| `Parser.new(source, max_depth: 128).parse` | Returns an immutable AST::Node; raises positioned syntax or invalid-value errors |
| `AST::Node` | Has `kind`, `value`, `children`, `start`, `finish`, and measured `depth` |
| `DataAccess.field(value, name)` | Resolves a string field name without creating a symbol |
| `DataAccess.array(value)` / `.object(value)` / `.string(value)` | Returns the supported conversion or nil; conversion defects propagate |
| `Types.name(value)` / `.falsey?(value)` / `.equal?(left, right)` | Provides one language type, truthiness rule, and equality rule |
| `ExpressionReference.new { |value| ... }.call(value)` | Evaluates a function expression reference inside one search |
| `Functions.new` | Creates an immutable empty registry |
| `Functions.default` | Returns the immutable built-in registry after Task 8 |
| `registry.with(name, signature:, variadic: false, override: false, &block)` | Returns a registry copy with one declared function |
| `registry.call(name, arguments, disable_visit_errors: false)` | Validates and calls the function; preserves callback exceptions |
| `Evaluator.new(functions:, disable_visit_errors: false).evaluate(node, data)` | Evaluates syntax without storing state in nodes |
| `JMESPath.compile(expression, cache_expressions: true, max_depth: 128)` | Returns an immutable Expression with reusable syntax |
| `JMESPath.search(expression, data, options = {}, **keywords)` | Loads input, compiles syntax, and evaluates through normalized options |
| `Expression#search(data, options = {}, **keywords)` | Reuses syntax with the same input and evaluation contracts |

Registry signatures are arrays of unions: `signature: [[:number], [:string, :null]]`.
Allowed types are `:any`, `:number`, `:string`, `:boolean`, `:null`, `:array`, `:object`, and `:expref`.
Also support homogeneous `:array_number` and `:array_string` descriptors.
When `variadic: true`, the last positional union repeats and its first occurrence is required.
For zero required arguments, use an empty signature without the variadic flag.
Reject invalid definitions, absent blocks, and duplicate names at registry construction.
Track built-in definitions internally so callback exceptions cannot be mistaken for suppressed validation errors.

An Expression stores its source, root node, and measured nesting depth.
Its `cache_expressions` option is accepted as a harmless compatibility option; evaluation already has compiled syntax.
Its `max_depth` option validates stored depth without reparsing; omitting it preserves the compilation limit.
Document these distinctions alongside the public options.

## File ownership

| Files | Responsibility |
| --- | --- |
| `jmespath-ruby.gemspec`, `Gemfile`, `Gemfile.lock`, `Rakefile`, `.rspec`, `.rubocop.yml`, `.gitignore`, `Steepfile` | Package metadata and reproducible development tasks |
| `lib/jmespath.rb`, `lib/jmespath/version.rb`, `errors.rb`, `options.rb`, `input.rb`, `expression.rb`, `cache.rb` | Public entry points and boundaries; relative paths use `lib/jmespath/` |
| `lib/jmespath/token.rb`, `lexer.rb`, `ast.rb`, `parser.rb`, `parser/expressions.rb`, `parser/projections.rb` | Tokenization and syntax construction |
| `lib/jmespath/data_access.rb`, `types.rb`, `expression_reference.rb`, `evaluator.rb`, `evaluation/*.rb` | Language values and evaluation |
| `lib/jmespath/functions.rb`, `functions/signature.rb`, `functions/scalar.rb`, `functions/collections.rb` | Function registration, validation, and built-ins |
| `sig/jmespath.rbs`, `sig/internal/*.rbs` | Packaged public signatures and development-only implementation contracts |
| `spec/{unit,integration,compatibility,documentation,packaging}/*_spec.rb`, `spec/support/*.rb` | Behavior checks and shared fixture adapters |
| `spec/fixtures/upstream/{python,ruby}/`, `spec/fixtures/upstream/sources.json`, `LICENSES/` | Pinned reference fixtures and attribution |
| `lib/jmespath/cli.rb`, `exe/jmespath`, `exe/jmespath.rb` | Testable CLI and minimal executable wrappers |
| `tasks/{quality,docs,package,release}.rake`, `script/{check_docs,benchmark,differential}.rb` | Ruby tooling, documentation validation, and comparison harnesses |
| `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, `VERSIONING.md`, `LICENSE`, `docs/guides/*.md` | Public guides and project policies |
| `.github/workflows/ci.yml` | Linux version matrix, macOS smoke tests, audit, and documentation artifacts |

## Reference inventory

Pin Python to `2812594e69d43098ef60f81f4efc404c071b0418` and Ruby to `5e86ea7da2e954cc12f5b3a8383a43c0a65acba7`.
Fetch GitHub content with `gh`; never resolve a floating branch during fixture import.

Import these 16 compliance files from each reference, preserving their bytes and relative filenames:

```text
basic.json       benchmarks.json  boolean.json      current.json
escape.json      filters.json     functions.json    identifiers.json
indices.json     literal.json     multiselect.json  pipe.json
slice.json       syntax.json      unicode.json      wildcard.json
```

Also import `tests/legacy/literal.json` from Python and `spec/legacy/literal.json` from Ruby.
Store them as `python/legacy/literal.json` and `ruby/legacy/literal.json`.
Each source manifest entry contains repository URL, commit, source path, local path, SHA-256, license, and local modifications.
Copy the corresponding upstream license files into `LICENSES/`; preserve applicable Apache notices.

Characterize these Ruby suites without preserving their private parser calls:

| Upstream suite | Behaviors to retain through public API tests |
| --- | --- |
| `spec/jmespath_spec.rb` | Hash search, Pathname, IO, Struct, scalar literals, floating-point comparisons |
| `spec/indifferent_access_spec.rb` | Symbol/string fields, nested Structs, missing Struct members |
| `spec/implicit_conversion_spec.rb` | `to_hash`, `to_ary`, selected wrapper identity, flattening wrappers, wrapped successful compliance cases |
| `spec/compliance_without_errors_spec.rb` | Type/arity suppression; syntax, invalid-value, and unknown-function propagation |
| `spec/compliance_spec.rb` and `spec/legacy/literal.json` | Successful queries, normalized error classes, accepted legacy literals |

Use all fixture files, including benchmark cases as semantic tests.
Deduplicate identical cases by provenance-aware IDs without dropping either source record.
Map errors to `SyntaxError`, `InvalidTypeError`, `InvalidValueError`, `InvalidArityError`, and `UnknownFunctionError` under `JMESPath::Errors`.
Document expected corrections from the design in `docs/guides/compatibility.md`; add separate regression tests.
Do not edit upstream fixture bytes to make tests pass.

## Task 1: Deliver a packaged lexer with positioned errors

**Files:** Create package/configuration files, `spec/spec_helper.rb`, `spec/unit/lexer_spec.rb`, `lib/jmespath/{version,errors,token,lexer}.rb`, `lib/jmespath.rb`, and initial signatures.

**Interfaces:** Consumes Ruby strings. Produces `Lexer#tokens`, immutable Token records, version `0.1.0`, and the complete named error hierarchy.

SyntaxError exposes `expression`, `position`, `line`, and `column`.
Define local test helpers `lex(source)`, `token_types(source)`, and `error_for(source)` around the real lexer.

- [ ] **Step 1:** Prepare the minimal package, tool configuration, version entry point, and test helper. Use `bundle install` after vetting dependencies. Start SimpleCov before the library loads. Configure Ruby 3.3 linting, randomized examples, and line/branch reporting.
- [ ] **Step 2:** Add lexer tests with these assertions:

```ruby
expect(token_types("foo[?bar >= `2`].name")).to eq(%i[identifier filter identifier gte literal rbracket dot identifier eof])
expect(lex("'café'").first.value).to eq("café")
expect(lex('"\\u2713"').first.value).to eq("✓")
expect { lex("'unfinished") }.to raise_error(JMESPath::Errors::SyntaxError)
expect(error_for("'✓' $").position).to eq(6)
expect(error_for("'✓' $").column).to eq(5)
```

- [ ] **Step 3:** Run `bundle exec rspec spec/unit/lexer_spec.rb`. Confirm failure identifies the missing lexer behavior.
- [ ] **Step 4:** Implement all grammar tokens, escaped quoted/raw strings, JSON literals, legacy bare literals, EOF, and byte spans. Add tests for every escape, invalid UTF-8, scalar JSON values, bad characters, and multiline positions.
- [ ] **Step 5:** Run the lexer specs, RuboCop, RBS validation, and Steep. Commit with `feat(lexer): tokenize JMESPath expressions` after they pass.

Development constraints: `rspec ~> 3.13`, `rubocop ~> 1.92`, `simplecov ~> 1.3`, `crap4ruby ~> 0.2.2`, `yard ~> 0.9.45`, `steep ~> 2.1`, `rbs ~> 4.2`, `rake ~> 13.4`, and `bundler-audit ~> 0.9.3`.
These stable release lines were checked against upstream tags; commit resolved versions in `Gemfile.lock` during execution.
Recheck upstream release metadata if execution selects a different release line.
Declare runtime dependencies `json >= 2.7, < 4` and `stringio >= 3.0, < 4`; use Ruby's Pathname library.
Keep development dependencies in the Gemfile, outside the gem's runtime metadata.

## Task 2: Define Ruby access and language value semantics

**Files:** Create `lib/jmespath/{data_access,types,expression_reference}.rb`, `spec/unit/{data_access,types}_spec.rb`, `spec/support/wrappers.rb`, and matching internal signatures.

**Interfaces:** Consumes supported Ruby values. Produces the DataAccess and Types methods defined above and callable ExpressionReference objects.

Wrapper fixtures mirror the pinned `to_hash` and `to_ary` protocols.
Use `Arrayish.new([1])` for `wrapped_array` and two distinct self-referencing arrays for cycle tests.

- [ ] **Step 1:** Write the access and semantic tests:

```ruby
expect(JMESPath::DataAccess.field({"x" => false, x: 7}, "x")).to be(false)
expect(JMESPath::DataAccess.field({"x" => nil, x: 7}, "x")).to eq(7)
expect(JMESPath::DataAccess.field(Struct.new(:x).new(3), "missing")).to be_nil
expect(JMESPath::DataAccess.field(Hashish.new("x" => wrapped_array), "x")).to equal(wrapped_array)
expect([nil, false, "", [], {}].all? { |v| JMESPath::Types.falsey?(v) }).to be(true)
expect(JMESPath::Types.falsey?(0)).to be(false)
expect(JMESPath::Types.equal?({"x" => [1]}, {"x" => [1.0]})).to be(true)
expect(JMESPath::Types.equal?({x: 1}, {"x" => 1})).to be(false)
expect { JMESPath::Types.equal?(cyclic_array, another_cyclic_array) }.to raise_error(JMESPath::Errors::InvalidValueError)
```

- [ ] **Step 2:** Run `bundle exec rspec spec/unit/data_access_spec.rb spec/unit/types_spec.rb`. Confirm the missing implementations cause failure.
- [ ] **Step 3:** Implement direct string-key access and explicit conversion adapters. Search pre-existing symbol keys by their names without interning queries. Restrict Struct access to members. Detect active recursion cycles during recursive normalization/equality.
- [ ] **Step 4:** Test malformed conversion returns, conversion exceptions, shared acyclic references, symbol/string collisions, structural comparison, and symbol-table growth. Run the targeted specs, RuboCop, and Steep; require success.
- [ ] **Step 5:** Commit with `feat(values): define Ruby adapters and JMESPath semantics`.

## Task 3: Parse the complete grammar into immutable syntax

**Files:** Create `lib/jmespath/{ast,parser}.rb`, `lib/jmespath/parser/{expressions,projections}.rb`, `spec/unit/parser_spec.rb`, `spec/support/ast_helpers.rb`, and signatures.

**Interfaces:** Consumes Token arrays through the lexer. Produces `Parser#parse` and AST::Node records with immutable literal templates and measured depth.

Define `parse(source)` in parser specs as `Parser.new(source).parse`.

- [ ] **Step 1:** Write parser assertions:

```ruby
expect(parse("a || b && c").kind).to eq(:or)
expect(parse("a || b && c").children.last.kind).to eq(:and)
expect(parse("items[?ok].name | [0]").kind).to eq(:pipe)
expect(parse("sort_by(items, &name)").children.last.kind).to eq(:expression_reference)
expect { parse("items[1:2:0]") }.to raise_error(JMESPath::Errors::InvalidValueError)
expect { parse("(" * 129 + "@" + ")" * 129) }.to raise_error(JMESPath::Errors::SyntaxError)
```

- [ ] **Step 2:** Run `bundle exec rspec spec/unit/parser_spec.rb`. Confirm missing parser behavior fails.
- [ ] **Step 3:** Implement Pratt precedence and projection boundaries from the specification and pinned Python parser. Define exact node layouts in `ast.rb` and their RBS contracts. Check depth before recursive descent; preserve flat sequences where possible.
- [ ] **Step 4:** Add AST tests for every production, malformed slices, delimiters, invalid subexpression literals, and function arguments. Include Unicode locations and limits 1 and 128. Test a 2,000-field chain without parser stack failure. Run parser/lexer specs, RuboCop, and Steep.
- [ ] **Step 5:** Commit with `feat(parser): parse the complete JMESPath grammar` after success.

## Task 4: Provide immutable custom functions and signature validation

**Files:** Create `lib/jmespath/functions.rb`, `lib/jmespath/functions/signature.rb`, `spec/unit/{functions,signature}_spec.rb`, and public/internal signatures.

**Interfaces:** Produces empty registries, `#with`, and `#call`. Function arguments may include ExpressionReference instances from Task 2.

- [ ] **Step 1:** Add registry tests:

```ruby
registry = JMESPath::Functions.new.with("double", signature: [[:number]]) { |n| n * 2 }
expect(registry.call("double", [3])).to eq(6)
expect { registry.call("double", [true]) }.to raise_error(JMESPath::Errors::InvalidTypeError)
expect { registry.call("double", []) }.to raise_error(JMESPath::Errors::InvalidArityError)
expect { registry.with("double", signature: [[:number]]) { 0 } }.to raise_error(ArgumentError)
expect { callback_raising_library_error.call("explode", [], disable_visit_errors: true) }.to raise_error(JMESPath::Errors::InvalidTypeError, "callback defect")
```

- [ ] **Step 2:** Run `bundle exec rspec spec/unit/functions_spec.rb spec/unit/signature_spec.rb`. Confirm failures identify missing registry contracts.
- [ ] **Step 3:** Implement immutable definitions and full argument validation. Support homogeneous typed arrays and unions. Separate validation suppression from callback execution; reserve internal built-in registration for later tasks.
- [ ] **Step 4:** Test every variadic argument, empty arrays, mixed typed arrays, explicit overrides, unknown names, and missing blocks. Include independent registry copies and original exception backtraces. Run targeted specs, RuboCop, RBS validation, and Steep.
- [ ] **Step 5:** Commit with `feat(functions): add immutable custom function registries` after success.

## Task 5: Evaluate scalar and constructed expressions

**Files:** Create `lib/jmespath/evaluator.rb`, `lib/jmespath/evaluation/{scalars,logic,construction}.rb`, `spec/unit/evaluator_spec.rb`, `spec/support/evaluate.rb`, and signatures.

**Interfaces:** Consumes Parser, DataAccess, Types, and Functions. Produces `Evaluator#evaluate` and expression-reference evaluation. The spec helper `evaluate(query, data, functions: Functions.new)` uses the real parser and evaluator.

- [ ] **Step 1:** Write evaluator assertions:

```ruby
expect(evaluate("foo.bar[-1]", {foo: {bar: [1, 2]}})).to eq(2)
expect(evaluate("a || 'fallback'", {a: []})).to eq("fallback")
expect(evaluate("a && unknown()", {a: false})).to be(false)
expect(evaluate("{a: missing, b: `false`}", {})).to eq("a" => nil, "b" => false)
expect(evaluate("`1` == `1.0`", {})).to be(true)
expect(evaluate("'a' < 'b'", {})).to be(true)
```

- [ ] **Step 2:** Run `bundle exec rspec spec/unit/evaluator_spec.rb`. Confirm missing evaluation behavior causes failure.
- [ ] **Step 3:** Implement current nodes, fields, literals, indices, grouping, subexpressions, pipes, comparisons, boolean operators, multiselects, and function dispatch. Keep traversal state outside syntax nodes. Copy mutable literal values when returning them.
- [ ] **Step 4:** Test null propagation, array/object equality, incompatible ordering, booleans versus numbers, short-circuit callbacks, and mutations of nested literal results. Run evaluator and earlier unit specs, RuboCop, and Steep.
- [ ] **Step 5:** Commit with `feat(evaluator): evaluate scalar and constructed expressions` after success.

## Task 6: Evaluate projections, filters, flattening, and slices

**Files:** Create `lib/jmespath/evaluation/{projections,slices}.rb`, `spec/unit/{projections,slices}_spec.rb`; modify evaluator dispatch and signatures.

**Interfaces:** Extends `Evaluator#evaluate` to every non-function language production without changing its signature.

- [ ] **Step 1:** Write projection and slicing assertions:

```ruby
expect(evaluate("items[*].x", {items: [{x: 1}, {}, {x: false}]})).to eq([1, false])
expect(evaluate("items[?ok].x", {items: [{ok: true, x: 1}, {ok: false, x: 2}]})).to eq([1])
expect(evaluate("[]", [[1, 2], [3, [4]]])).to eq([1, 2, 3, [4]])
expect(evaluate("[::-1]", [0, 1, 2])).to eq([2, 1, 0])
expect(evaluate("[0:0:-1]", [0, 1, 2])).to eq([])
expect(evaluate("[:0:-1]", [0, 1, 2])).to eq([2, 1])
```

- [ ] **Step 2:** Run `bundle exec rspec spec/unit/projections_spec.rb spec/unit/slices_spec.rb`. Confirm the new node kinds fail.
- [ ] **Step 3:** Implement Python-compatible slice normalization, including omitted negative-stop sentinels. Preserve one-level flattening and null omission. Respect pipe/projection precedence and wrong-container nil results.
- [ ] **Step 4:** Test nested projections, object values, Structs, wrapped arrays, negative bounds, large strides, empty lists, multiselect projection boundaries, and wide chains. Run all non-function language unit specs, RuboCop, and Steep.
- [ ] **Step 5:** Commit with `feat(evaluator): evaluate projections filters and slices` after success.

## Task 7: Implement scalar and conversion built-ins

**Files:** Create `lib/jmespath/functions/scalar.rb`, `spec/unit/scalar_functions_spec.rb`; modify registry internals and signatures.

**Interfaces:** Produces `Functions::Scalar.register(registry) -> Functions`, adding `abs`, `ceil`, `floor`, `contains`, `ends_with`, `starts_with`, `length`, `reverse`, `type`, `to_array`, `to_string`, `to_number`, and `not_null`.

Define `evaluate_with_scalars` using the Task 5 helper and the registry returned by `Scalar.register(Functions.new)`.

- [ ] **Step 1:** Write built-in assertions:

```ruby
expect(evaluate_with_scalars("not_null(a, `false`, `3`)", {})).to be(false)
expect(evaluate_with_scalars("to_number('12.5')", {})).to eq(12.5)
expect(evaluate_with_scalars("to_number(`true`)", {})).to be_nil
expect(evaluate_with_scalars("length('✓é')", {})).to eq(2)
expect { evaluate_with_scalars("reverse('a', 'b')", {}) }.to raise_error(JMESPath::Errors::InvalidArityError)
expect { evaluate_with_scalars("to_array()", {}) }.to raise_error(JMESPath::Errors::InvalidArityError)
```

- [ ] **Step 2:** Run `bundle exec rspec spec/unit/scalar_functions_spec.rb`. Confirm unknown-function failures for missing built-ins.
- [ ] **Step 3:** Implement signatures and function bodies using the shared type/access model. Use JSON for conversion without permitting additions or query-controlled parser options. Map cyclic conversion failures to InvalidValueError. Preserve identity where a conversion returns an already valid value.
- [ ] **Step 4:** Test every registered function's valid result, wrong arity, wrong type, Unicode, null, and empty input. Test finite-number rules, numeric parsing failures, and suppression boundaries. Run targeted specs, RuboCop, and Steep.
- [ ] **Step 5:** Commit with `feat(functions): implement scalar and conversion built-ins` after success.

## Task 8: Implement collection and expression-reference built-ins

**Files:** Create `lib/jmespath/functions/collections.rb`, `spec/unit/collection_functions_spec.rb`; finish `Functions.default` and signatures.

**Interfaces:** Produces `Functions::Collections.register(registry) -> Functions` and `Functions.default`. Adds `avg`, `sum`, `min`, `max`, `sort`, `join`, `keys`, `values`, `merge`, `map`, `sort_by`, `min_by`, and `max_by`.

Define `evaluate_with_builtins` using the Task 5 helper with `Functions.default`.

- [ ] **Step 1:** Write collection assertions:

```ruby
expect(evaluate_with_builtins("map(&x, @)", [{x: 1}, {}])).to eq([1, nil])
expect(evaluate_with_builtins("min_by(@, &x)", [])).to be_nil
expect(evaluate_with_builtins("sort_by(@, &rank)[*].id", [{rank: 1, id: "a"}, {rank: 1, id: "b"}])).to eq(["a", "b"])
expect { evaluate_with_builtins("merge(`{}`, `1`)", {}) }.to raise_error(JMESPath::Errors::InvalidTypeError)
expect { evaluate_with_builtins("to_string(@)", cyclic_hash) }.to raise_error(JMESPath::Errors::InvalidValueError)
```

- [ ] **Step 2:** Run `bundle exec rspec spec/unit/collection_functions_spec.rb`. Confirm missing collection behavior fails.
- [ ] **Step 3:** Implement all collection signatures, stable sorting, homogeneous key validation, empty-array behavior, and expression-reference calls. Complete the frozen default registry. Map recursive-conversion cycles to InvalidValueError.
- [ ] **Step 4:** Test all 13 functions, including variadic trailing arguments, wrappers, mixed key types, ties, and empty inputs. Run all function and evaluator unit specs, RuboCop, and Steep.
- [ ] **Step 5:** Commit with `feat(functions): implement collection and reference built-ins` after success.

## Task 9: Expose search, compilation, input handling, and bounded caching

**Files:** Create `lib/jmespath/{options,input,expression,cache}.rb`, `spec/integration/{search,compilation,concurrency}_spec.rb`, `spec/unit/{options,cache}_spec.rb`; complete `lib/jmespath.rb` and public signatures.

**Interfaces:** Produces the public search and compile signatures from Shared interfaces. `Cache#fetch(source, max_depth:) { ... }` stores only immutable Expression objects. `Input.load(data)` consumes supported IO/path inputs and otherwise preserves data.

- [ ] **Step 1:** Write public assertions:

```ruby
expect(JMESPath.search("foo.bar", {foo: {bar: "value"}})).to eq("value")
expect(JMESPath.compile("foo").search({foo: 3})).to eq(3)
expect(JMESPath.search("foo", StringIO.new('{"foo":4}'))).to eq(4)
expect { JMESPath.search("foo", {}, {cache_expressions: false}, cache_expressions: true) }.to raise_error(ArgumentError)
expect { JMESPath.search("explode()", {}, functions: custom_error_registry, disable_visit_errors: true) }.to raise_error(JMESPath::Errors::InvalidTypeError, "callback defect")
```

- [ ] **Step 2:** Run `bundle exec rspec spec/integration/search_spec.rb spec/integration/compilation_spec.rb spec/unit/cache_spec.rb`. Confirm missing public API behavior fails.
- [ ] **Step 3:** Implement normalization, JSON input, immutable Expression, and synchronized bounded caching. Compile outside locks. Suppress only the library validation errors specified above. Bind function registries per evaluation, never through cached syntax.
- [ ] **Step 4:** Test 256-entry eviction and the 1,048,576-byte budget using small injected cache capacities for boundary examples. Test oversized bypass, mutable source strings, failed parses, custom registry isolation, IO position/ownership, and nesting-option semantics. Run 16 threads performing 100 mixed cached searches each, with exact results and propagated thread errors.
- [ ] **Step 5:** Run all unit/integration specs, RuboCop, RBS validation, and Steep. Commit with `feat(api): expose compatible search and compiled expressions` after success.

## Task 10: Establish compliance, Ruby compatibility, and differential evidence

**Files:** Create the complete upstream fixture inventory, `LICENSES/`, `spec/support/compliance.rb`, `spec/integration/compliance_spec.rb`, `spec/compatibility/{ruby_api,legacy,errors}_spec.rb`, `script/differential.rb`, and `docs/guides/compatibility.md`.

**Interfaces:** The fixture adapter yields `{id, expression, given, expected_result, expected_error, source}`. `ruby script/differential.rb --python-root PATH --ruby-root PATH` compares isolated reference processes using JSON lines.

- [ ] **Step 1:** Import the exact inventory with hashes and licenses. Add manifest-integrity tests, one example per semantic case, and characterization assertions for every listed Ruby suite.
- [ ] **Step 2:** Run `bundle exec rspec spec/integration/compliance_spec.rb spec/compatibility`. Inject an incorrect result through a test-only adapter and verify harness failure. Restore that adapter without changing upstream fixture bytes. Record genuine implementation failures before repairs.
- [ ] **Step 3:** Fix implementation defects with targeted regression tests and separate `fix(compatibility)` commits. Preserve upstream bytes. Record each approved correction separately with provenance, exact behavior, and migration impact. Stop for a user decision if another material compatibility conflict appears.
- [ ] **Step 4:** Run all fixtures offline, including wrapped successful cases and visit-error suppression. Compare deterministic valid generated cases and all JSON-compatible reference cases in isolated processes. Report input count, disagreements, approved corrections, and reference commits; require zero unexplained disagreements.
- [ ] **Step 5:** Run the complete specs and type/lint checks. Commit with `test(compliance): verify pinned Python and Ruby contracts` after success.

Reference checkout preparation uses `gh` and temporary directories. The differential harness must require explicit checkout paths and perform no downloads or installs.
Normalize error categories without swallowing crashes, invalid JSON, or failed reference processes.
Keep Python outside the normal test command and retain its comparison evidence in the compatibility guide.

## Task 11: Ship both command-line entry points

**Files:** Create `lib/jmespath/cli.rb`, `exe/jmespath`, `exe/jmespath.rb`, `spec/integration/cli_spec.rb`; modify gemspec executables and signatures.

**Interfaces:** `CLI.run(argv, stdin:, stdout:, stderr:) -> Integer` returns 0 for success, 2 for usage errors, and 1 for malformed JSON or query errors.

- [ ] **Step 1:** Test `CLI.run` with injected StringIO streams, then repeat entry-point smoke cases through subprocesses. Assert `foo.bar` with `{"foo":{"bar":2}}` returns status 0 and stdout `"2\n"`. Assert null prints `"null\n"`, help/version succeed, and malformed JSON leaves stdout empty with status 1.
- [ ] **Step 2:** Run `bundle exec rspec spec/integration/cli_spec.rb`. Confirm missing executables fail.
- [ ] **Step 3:** Implement the injectable CLI and thin wrappers. Accept exactly one expression argument except help/version. Catch declared user-input failures only; leave unexpected failures visible.
- [ ] **Step 4:** Test both names, Unicode JSON, missing/excess arguments, invalid expressions, unknown functions, and broken input reads. Run CLI specs, RuboCop, and Steep.
- [ ] **Step 5:** Commit with `feat(cli): provide compatible JSON query commands` after success.

## Task 12: Make documentation and all quality gates executable

**Files:** Create `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `VERSIONING.md`, `.yardopts`, `docs/guides/{search,compilation,functions,errors,performance}.md`, `tasks/{quality,docs}.rake`, `script/check_docs.rb`, and `spec/documentation/examples_spec.rb`. Complete YARD tags and signatures across the library.

**Interfaces:** `rake docs:check` checks public documentation, tags, references, and local links. `rake docs` generates HTML. The default `rake` task runs lint, types, fresh specs/coverage, coverage-aware CRAP, and documentation checks.

`ruby script/check_docs.rb --root PATH` checks that repository or a temporary fixture, returning 0 for success and 1 for findings.

- [ ] **Step 1:** Add failing checks for an undocumented public method, broken YARD reference, missing local link, and a wrong documented example result. Use small temporary fixtures for checker tests; do not damage authored documentation.
- [ ] **Step 2:** Run `bundle exec rspec spec/documentation/examples_spec.rb` and the checker tests. Confirm each deliberate defect is detected before adding the correct docs.
- [ ] **Step 3:** Write the guide set and public YARD contracts. Extract `#=>` examples and expected-error markers from trusted repository docs into RSpec execution. Make the docs the single source for those examples. Check public RBS signatures and all implementation files with Steep.
- [ ] **Step 4:** Configure fresh, nonmerged coverage for every library file. Run crap4ruby with `lib --coverage coverage/.resultset.json --threshold 10 --no-save` only after that suite. Report N/A methods explicitly. Add `rake audit` for network-dependent advisory updates, outside default checks.
- [ ] **Step 5:** Run `bundle exec rake` and `bundle exec rake docs`. Require 100% line coverage, at least 95% branch coverage, CRAP at most 10, no lint/type/documentation errors, and generated HTML. Commit with `docs(api): validate guides types and public examples`.

Document return identity, literal copying, callback obligations, threading, input ownership, errors, all options, and the nesting bound.
Document migration from `jmespath` and the inability to satisfy its transitive dependency name.
Public documentation must not imply both providers can share one bundle safely.
Use `rake audit` to fail on known vulnerabilities, with explicit database freshness and failure reporting.

## Task 13: Measure representative performance without changing semantics

**Files:** Create `script/benchmark.rb`, `benchmark/{queries.json,documents.json}`, and `docs/guides/performance.md`; add narrow regression tests if optimization changes code.

**Interfaces:** `ruby script/benchmark.rb --ruby-root PATH --iterations 1000` emits JSON measurements and verifies expected results. It measures one-shot startup, warmed convenience search, compiled reuse, and cache churn independently.

- [ ] **Step 1:** Add a harness smoke test rejecting a wrong expected result. Assert elapsed seconds and allocated-object counts appear for a tiny workload.
- [ ] **Step 2:** Run that test and confirm the missing harness fails.
- [ ] **Step 3:** Implement the standard-library Ruby harness with isolated reference processes, alternating run order, warmup, and workload hashes. Include field traversal, projections, filters, sort functions, slicing, Unicode, and cache misses.
- [ ] **Step 4:** Run at least five paired measurements per workload with the same MRI/JIT configuration. Record medians, allocation counts, versions, fixture hashes, and commands. Investigate material regressions; require targeted red/green tests for any optimization.
- [ ] **Step 5:** Run the harness smoke test and `bundle exec rake`. Commit with `perf(benchmarks): measure search and compilation workloads` after success.

## Task 14: Verify installed artifacts and the supported Ruby matrix

**Files:** Create `spec/packaging/gem_spec.rb`, `tasks/{package,release}.rake`, `.github/workflows/ci.yml`, `CHANGELOG.md`, and final license/provenance files. Finalize the gemspec file allowlist.

**Interfaces:** `rake build` creates `pkg/jmespath-ruby-0.1.0.gem`. `rake package:check` builds, installs into a temporary isolated bundle, and exercises only packaged files. `rake release:check` performs local release validation without publication.

- [ ] **Step 1:** Add packaging tests asserting the require path, version, search, both executables, public signatures, guides, licenses, and clean gem manifest. Assert no specs, caches, secrets, coverage, internal signatures, or generated HTML enter the gem.
- [ ] **Step 2:** Run `bundle exec rspec spec/packaging/gem_spec.rb`. Confirm missing packaged features or manifest entries fail before fixing packaging.
- [ ] **Step 3:** Implement a production-only isolated bundle using the built artifact and its declared runtime dependencies. Seed its cache from local gem archives and run `bundle install --local`; normal packaging specs must stay offline. Verify `$LOADED_FEATURES` resolves this artifact's `jmespath.rb`. Run smoke commands outside the repository to prevent load-path contamination.
- [ ] **Step 4:** Configure Linux Ruby 3.3/3.4/4.0 checks, macOS installed-gem/CLI smoke tests, a dependency audit, and uploaded YARD HTML. Verify action publishers and immutable revisions before adding workflow references. Do not add a publishing workflow or credentials.
- [ ] **Step 5:** Run `mise exec ruby@3.3.11 -- bundle exec rake`, `mise exec ruby@3.4.9 -- bundle exec rake`, and `mise exec ruby@4.0.9 -- bundle exec rake` after installing the locked bundle for each interpreter. Run package/release checks and the audit. Commit with `ci(quality): verify Ruby support and installed gem artifacts`.

Each matrix interpreter may need its compatible Bundler installed through upstream instructions.
Track the exact local and remote checks separately; an authored workflow is not evidence that hosted CI passed.
Remove scratch scripts and temporary reference checkouts after their evidence is recorded.
Finish with a review against the approved design, required by the selected execution workflow.
Report how to run `bundle exec rake`, use the API, and query standard input through either executable.

## Self-review record

The task map covers every design section: language and adapters (1-8), API/cache (9), reference evidence (10), CLI (11), documentation/tooling (12), measurements (13), and delivery (14).
All five Review focus items have tests assigned to their owning tasks.
Shared signatures and option names are defined once above and referenced by subsequent tasks.
Final release checks enforce the approved thresholds; unfinished intermediate tasks do not establish release readiness.
The plan requires no publication, remote repository, or external account setup.
