# Syntax validation implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate syntax through Ruby and both CLI executables without input documents or callback execution, for issue #28.

**Architecture:** Call the parser directly and convert its first syntax failure into an immutable record. Extend the formatter to accept that record. Dispatch CLI validation before reading stdin.

**Tech Stack:** Ruby 3.3+, RSpec, RBS, Steep, YARD, and existing Rake tasks.

**Spec:** [Approved design](../specs/2026-11-02-syntax-validation-design.md).

## Global constraints

- Use existing dependencies and preserve imported compliance fixtures.
- Preserve compilation, search, standard syntax, and imported compliance fixtures.
- Require a String expression and an Integer `max_depth` from 1 through 128.
- Rescue only `JMESPath::Errors::SyntaxError`; unrelated exceptions propagate.
- Validation never reads stdin or evaluates data.
- Unknown functions and invalid runtime argument types or counts remain valid syntax.
- Return a frozen array: empty for valid syntax, or containing one `JMESPath::SyntaxDiagnostic` for the first syntax failure.

## Review focus

- R1: Invalid method arguments take precedence over syntax failures, including invalid encodings.
- R2: Non-UTF-8 source conversion preserves agreement with compilation coordinates and leaves caller strings mutable.
- R3: Validation bypasses function lookup, callbacks, execution plans, and the compilation cache.
- R4: Flag-like expressions after `--validate` are parsed as query text, including `--help` and `--version`.
- R5: Validation terminates while executable stdin remains open, without waiting for input or EOF.

## Task 1: Add immutable diagnostics and Ruby syntax validation

**Files:**

- Create `lib/jmespath/syntax_diagnostic.rb` and `spec/unit/syntax_validation_spec.rb`.
- Modify `lib/jmespath.rb`, `lib/jmespath/diagnostic.rb`, `sig/jmespath.rbs`, and `sig/internal/diagnostic.rbs`.
- Modify `spec/unit/diagnostic_spec.rb` and `docs/guides/errors.md`.

**Interfaces:**

- Consume `Parser.new(source, max_depth: depth).parse` and `Errors::SyntaxError` structured fields.
- Produce `JMESPath.validate(String, max_depth: Integer = 128) -> Array[SyntaxDiagnostic]`.
- Produce `SyntaxDiagnostic` readers `reason: String`, `expression: String`, and `position`, `line`, `column`: `Integer?`.
- Produce `SyntaxDiagnostic#location_known? -> bool`.
- Extend `Diagnostic.format(Errors::SyntaxError | SyntaxDiagnostic) -> String`.
- Use an internal `SyntaxDiagnostic.new(error)` constructor, documented with `@api private` and declared in RBS.

- [ ] **Step 1: Add failing Ruby contract tests.**

Include named examples for valid syntax, first-failure metadata, and record freezing:

```ruby
expect(JMESPath.validate("items[*].name")).to eq([])
expect(JMESPath.validate("items[*].name")).to be_frozen
result = JMESPath.validate("items[?active")
expect(result.length).to eq(1)
expect(result).to be_frozen
diagnostic = result.fetch(0)
expect(diagnostic).to be_a(JMESPath::SyntaxDiagnostic)
expect(diagnostic).to be_frozen
expect(diagnostic.reason).to eq("Expected rbracket, received eof")
expect(diagnostic.expression).to eq("items[?active")
expect([diagnostic.position, diagnostic.line, diagnostic.column]).to eq([13, 1, 14])
expect(diagnostic.location_known?).to be(true)
expect(JMESPath::Diagnostic.format(diagnostic))
  .to eq("Expected rbracket, received eof at line 1, column 14\nitems[?active\n             ^")
```

Cover empty input, malformed operators, unterminated quotes, trailing LF, tabs, controls, Unicode, multiline queries, and nesting failures.
Reuse diagnostic-spec inputs, with expected coordinates independent of the implementation.
Check valid examples `unknown()`, `length()`, `length(\`4\`)`, and `[::0]` without evaluation.
Compare acceptance and failure fields with uncached `compile` across valid, invalid, encoding, and depth cases.
For invalid UTF-8 and binary `"\xFF"`, assert the reason is `Expression has invalid encoding`.
Assert encoding diagnostics have empty expressions, nil coordinates, false `location_known?`, and reason-only formatting.
Test depth boundaries 1 and 128 with `@`, plus a nested expression rejected at depth 1.
Test mutation attempts on returned strings and arrays, expecting `FrozenError`.
Change a mutable source after validation; assert stored text remains unchanged and the source remains unfrozen.

For R1, reject `nil`, symbols, and numbers as expressions with `ArgumentError`.
Reject depth values `nil`, `true`, `0`, `129`, `1.0`, and `"1"` with `ArgumentError`.
Use invalid syntax and invalid UTF-8 when testing invalid depth precedence.
Reject keywords `functions`, `cache_expressions`, `disable_visit_errors`, and an unknown keyword with `ArgumentError`.
For R2, validate `"'café' $".encode(Encoding::ISO_8859_1)` and compare its failure with uncached compilation.
Assert its diagnostic expression is UTF-8 and its byte position is 8, line 1, column 8.
For R3, install raising spies on `Plan.build`, `Cache#fetch`, `Functions#definition`, and `Functions#call` during validation.
Register a raising custom callback in a test registry; assert its query validates without invoking the callback.
Inject an unrelated parser exception and assert the same exception propagates.

- [ ] **Step 2: Run the failing tests.**

Run `bundle exec rspec spec/unit/syntax_validation_spec.rb spec/unit/diagnostic_spec.rb`.
Expected: missing `validate` or `SyntaxDiagnostic` failures, with prior formatter tests still passing.

- [ ] **Step 3: Implement the Ruby contract and documentation.**

Require the record from `lib/jmespath.rb`; copy only syntax error data and freeze the record and its strings.
Derive known coordinates from the error; use nil coordinates for unknown locations without retaining the exception.
Validate argument types and depth before calling the parser; leave `compile`, `Options`, and parser behavior unchanged.
Return a frozen empty array on success, or a frozen singleton array after rescuing a syntax error.
Extend formatter types and narrow nullable positions after the location guard, preserving all prior formatting rules.
Add public RBS declarations for the method, record, constructor, and formatter union.
Update internal formatter signatures for the same union.
Add YARD types and executable examples for validation and record readers.
Document syntax-only acceptance, the single-failure limit, coordinate rules, and invalid-argument exceptions in the errors guide.

- [ ] **Step 4: Verify Ruby behavior, types, and examples.**

Run `bundle exec rspec spec/unit/syntax_validation_spec.rb spec/unit/diagnostic_spec.rb spec/unit/errors_spec.rb spec/integration/compilation_spec.rb`.
Run `bundle exec rake types docs:check`.
Expected: zero test failures, type errors, and documentation errors.

- [ ] **Step 5: Commit only Task 1 files.**

Use `feat(validation): add immutable syntax diagnostics`.

## Task 2: Add CLI validation without stdin reads

**Files:**

- Modify `lib/jmespath/cli.rb` and `sig/internal/cli.rbs` for any private helper declarations.
- Modify `spec/integration/cli_spec.rb`, `docs/guides/errors.md`, and `README.md`.
- Modify `script/support/package_check.rb` and `spec/packaging/gem_spec.rb` to exercise validation from the installed artifact.

**Interfaces:**

- Consume Task 1 `JMESPath.validate` and `Diagnostic.format`.
- Extend `CLI.run(argv, stdin:, stdout:, stderr:) -> Integer` with `--validate EXPRESSION`.
- Both executables already delegate to `CLI.run`; preserve their entry points.

- [ ] **Step 1: Add failing CLI tests and update usage expectations.**

Use an unreadable stdin double for these cases:

| Arguments | Status | stdout | stderr |
| --- | --- | --- | --- |
| `["--validate", "unknown()"]` | 0 | Empty | Empty |
| `["--validate", "length()"]` | 0 | Empty | Empty |
| `["--validate", "items[?active"]` | 1 | Empty | Task 1 formatted diagnostic plus LF |
| `["--validate", ""]` | 1 | Empty | Empty-expression diagnostic plus LF |
| `["--validate"]` | 2 | Empty | Usage plus LF |
| `["--validate", "@", "extra"]` | 2 | Empty | Usage plus LF |

Keep the search usage line and append `       jmespath --validate EXPRESSION` on its own line.
Update every exact usage assertion, including subprocess assertions, to expect both lines.
For R4, check `--validate --help` and `--validate --version` return syntax status 1 without informational output.
Check help documents syntax-only validation, stdin independence, and status codes.
Inject an unrelated validation exception; assert identity-preserving propagation.
Verify existing search output, runtime errors, malformed JSON behavior, and help/version behavior through their retained tests.

For R5, launch each executable with `Open3.popen3` and keep its stdin writer open.
Assert successful and invalid validation exit within five seconds, before closing stdin.
Read stdout and stderr after process exit; assert exact output and status.
Use `Timeout.timeout` and ensure timed-out children are terminated and reaped.
Add executable cases for missing and excess validation arguments, with status 2 and exact usage output.
In the packaging spec, assert the artifact includes `lib/jmespath/syntax_diagnostic.rb`.
Assert package verification returns `validation: []` and `syntax_failure: "Expected rbracket, received eof"` as string-keyed JSON fields.

- [ ] **Step 2: Run the failing CLI tests.**

Run `bundle exec rspec spec/integration/cli_spec.rb spec/packaging/gem_spec.rb`.
Expected: validation fails under the search-only dispatcher; changed usage expectations also fail.

- [ ] **Step 3: Implement CLI dispatch and document use.**

Recognize a leading `--validate` before informational dispatch and the JSON read.
Require exactly two arguments for validation and pass the second token unchanged as query text.
Return 0 silently for no diagnostics; otherwise print the formatted diagnostic to stderr and return 1.
Return usage status 2 for missing or excess arguments without reading stdin.
Preserve search behavior and update help with the syntax-only limitation and stdin independence.
Add the standalone shell command `jmespath --validate 'items[*].name'` to the README and errors guide.
Document empty success output, syntax failure output, and statuses 0, 1, and 2.
Keep JSON output, stdin query input, and CLI depth configuration outside scope.
Extend `PackageCheck::SMOKE` with valid-query validation and the reason from validating `items[?active`.
Include these as `validation` and `syntax_failure` fields in its JSON result.

- [ ] **Step 4: Verify CLI behavior and complete required checks.**

Run `bundle exec rspec spec/integration/cli_spec.rb spec/unit/syntax_validation_spec.rb spec/unit/diagnostic_spec.rb`.
Run `bundle exec rake`, then `bundle exec rake docs`.
Run `bundle exec rake package:check` to verify the added library file in an offline gem installation.
Expected: zero failures, full line and branch coverage, valid types, generated docs, and successful package verification.

- [ ] **Step 5: Commit only Task 2 files.**

Use `feat(cli): validate queries without reading stdin`.
Report Ruby and shell examples with verification evidence; leave release and remote operations outside this plan.
