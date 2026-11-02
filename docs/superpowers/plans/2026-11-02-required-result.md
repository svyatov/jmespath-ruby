# Required query results implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Expression#fetch` to require a non-null result without changing nullable searches.

**Architecture:** Call `search` once and reject only a nil final result. Raise a dedicated runtime error containing immutable query text. Reuse input loading and option handling unchanged.

**Tech Stack:** Ruby 3.3 or later, RSpec, RBS, Steep, YARD, and the locked development bundle.

**Spec:** [Approved required-result design](../specs/2026-11-02-required-result-design.md).

## Global constraints

Preserve standard JMESPath semantics and the nullable behavior of `search` and `call`.
Exclude missing-versus-null detection, fallback values, block defaults, CLI changes, dependencies, and evaluation refactoring.
Preserve imported compliance fixtures and unrelated `oss-audit-report.md`.
Use the message `Expression returned null`.
Preserve exception identity and backtrace for failures raised during evaluation.

## Review focus

- R1: A recovered intermediate nil must succeed when the final result is non-nil.
- R2: Callback exceptions resembling library validation failures must propagate under saved suppression.
- R3: Conflicting options must fail before a stream is read.
- R4: One fetch must invoke a side-effecting callback only once, including when it returns nil.
- R5: Caller mutation of query text must not change compiled source or stored error text.

## File structure

| File | Responsibility |
| --- | --- |
| `lib/jmespath/expression.rb` | Add the public wrapper and its YARD documentation |
| `lib/jmespath/errors.rb` | Define the dedicated error and immutable expression attribute |
| `sig/jmespath.rbs` | Declare the method, error constructor, and attribute |
| `spec/integration/required_result_spec.rb` | Exercise public fetch behavior and compatibility |
| `spec/unit/errors_spec.rb` | Verify manual error construction and text ownership |
| `README.md`, `docs/guides/compilation.md`, `docs/guides/errors.md` | Explain required results with executable examples |

### Task 1: Deliver required-result queries

**Interfaces:** Consume `Expression#search(data, options = Options::EMPTY, **keywords)` and `Expression#source`.
Produce `Expression#fetch(data, options = Options::EMPTY, **keywords)`, returning the exact non-nil result.
Produce `Errors::NullResultError < Errors::RuntimeError`, with `initialize(expression:)` and read-only `expression`.
The initializer stores an independent frozen copy and sets the fixed message.
The RBS method returns `Object`; the constructor takes `expression: String` and the attribute returns `String`.

- [ ] **Step 1: Add failing error and public regression tests.**

Create `spec/integration/required_result_spec.rb` and extend `spec/unit/errors_spec.rb`.
Use the following assertions as the core tests:

```ruby
query = JMESPath.compile("user.name")
expect(query.fetch({ user: { name: "Ada" } })).to eq("Ada")
expect { query.fetch({}) }.to raise_error(JMESPath::Errors::NullResultError) { |error|
  expect(error.message).to eq("Expression returned null")
  expect(error.expression).to eq("user.name")
  expect(error.expression).to be_frozen
  expect(error).to be_a(JMESPath::Errors::RuntimeError)
}
[false, 0, "", [], {}].each do |value|
  expect(JMESPath.compile("value").fetch({ value: value })).to equal(value)
end
expect(JMESPath.compile("value || `false`").fetch({})).to be(false) # R1
```

Add individually named examples covering the following exact contracts:

| Example | Assertions |
| --- | --- |
| Rejects null final results | Missing `user.name`, explicit nil, and `items[3]` on an empty array raise `NullResultError` |
| Honors suppression and overrides | Saved suppression rejects nil from `length(@)` on `7` and `length()`; overriding suppression to false restores the original validation classes |
| Forwards positional and keyword options | Positional suppression works; keyword registry overrides preserve saved suppression; later calls retain saved defaults |
| Preserves successful identity | Selected strings, arrays, and hashes are the original mutable objects |
| Supports input forms | Hash, Array, Struct, StringIO, IO, and Pathname produce the same results as `search`; streams remain caller-owned |
| Propagates application failures, R2 | A callback raises a pre-created `InvalidTypeError` with an explicit backtrace under saved suppression; the rescued object and backtrace remain unchanged |
| Rejects conflicts before input, R3 | Conflicting positional and keyword suppression raises `ArgumentError`; an instrumented StringIO receives no `read` call |
| Evaluates once, R4 | A counted custom callback returning either false or nil runs exactly once per fetch |
| Owns expression text, R5 | Mutating the original compile string preserves the error's query text; manually constructed errors copy and freeze their supplied text |
| Propagates other failures | Invalid JSON, unknown functions, invalid slice steps, invalid options, and nesting-limit failures retain their search error classes |
| Preserves nullable entry points | `query.search({})` and `query.call({})` still return nil |

- [ ] **Step 2: Confirm the tests fail for missing interfaces.**

Run `bundle exec rspec spec/unit/errors_spec.rb spec/integration/required_result_spec.rb`.
Expected: failures naming the missing `NullResultError` or `fetch`, with no unrelated setup failures.

- [ ] **Step 3: Implement the public error, wrapper, and signatures.**

Add the interfaces above to `lib/jmespath/errors.rb`, `lib/jmespath/expression.rb`, and `sig/jmespath.rbs`.
Forward all arguments directly to `search`, check `nil?`, and preserve the successful result.
Add YARD parameter, return, exception, and executable-example documentation for both public interfaces.
Keep the evaluator, compiled plan, and suppression implementation unchanged.

- [ ] **Step 4: Verify the focused regression suite.**

Run `bundle exec rspec spec/unit/errors_spec.rb spec/integration/required_result_spec.rb spec/integration/configured_queries_spec.rb spec/integration/compilation_spec.rb`.
Expected: all examples pass.

- [ ] **Step 5: Document required-result behavior.**

Add a successful `fetch` example to `README.md` and executable success and failure examples to the compilation guide.
Add the error to the errors guide, including its expression attribute and suppression behavior.
Explain that false and empty values succeed and that missing and explicit null receive the same error.

- [ ] **Step 6: Run the full gates.**

Run `env RUBOCOP_CACHE_ROOT=/private/tmp/jmespath-rubocop-cache bundle exec rake`.
Expected: lint, RBS, Steep, all specs, 100% line and branch coverage, CRAP, and executable documentation checks pass.
Run `bundle exec rake docs`.
Expected: YARD completes without warnings.
Run `git diff --check` and inspect the diff for unrelated edits and fixture changes.

- [ ] **Step 7: Commit the tested feature.**

Stage only the eight implementation, test, signature, and guide files in the file structure table.
Commit with `feat(expression): require non-null results with fetch`.
Keep plan progress updates explicit and preserve unrelated work.

- [ ] **Step 8: Verify behavior and review the completed change.**

Exercise successful false and missing-field cases through `bundle exec ruby -Ilib -rjmespath`.
Expected: false returns unchanged; missing data raises `NullResultError` containing the query text.
Use an independent reviewer to check the final diff against the spec, especially R1 through R5.
Resolve verified findings and rerun affected checks before reporting completion.
