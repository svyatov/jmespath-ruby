# Readable CLI diagnostics implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show located query failures and structured function details on stderr through both CLI executables.

**Architecture:** Route expected failures through a private `CLI::FailureDiagnostic` formatter. Reuse `JMESPath::Diagnostic.format` for syntax, source rendering, and control escaping. Adapt runtime metadata through temporary syntax-error objects without changing original exceptions or public interfaces.

**Tech Stack:** Ruby 3.3+, RSpec, RBS, Steep, YARD, and installed development tools.

**Spec:** [Approved design](../specs/2026-11-02-cli-diagnostics-design.md).

## Global constraints

- Successful JSON output, parsing order, exception messages, and query semantics remain unchanged.
- Failures before output starts leave stdout empty.
- Do not catch arbitrary application exceptions or add dependencies.
- Usage failures retain status 2 and do not read stdin.
- Help and version requests retain status 0 and do not read stdin.
- Unknown-function failures retain their messages, including suggestions supplied by issue #25.
- Add no colors, flags, backtraces, input values, or document excerpts.
- Preserve public RBS and YARD contracts, imported fixtures, and the unrelated untracked `oss-audit-report.md`.
- Future CLI modes remain assigned to their feature issues.

## Review focus

- R1: Nested calls must identify the failing inner function. Exercise `length(reverse(@))` in Task 1.
- R2: Multibyte prefixes must preserve character columns. Exercise `['✓', length(@)]` in Task 1.
- R3: Partial metadata must retain usable location information. Inject incomplete errors in Task 1.
- R4: Invalid range endpoints must suppress misleading carets. Cover range and encoding boundaries in Task 1.
- R5: Parser messages must not expose document fragments. Use a unique malformed-input marker in Task 2.

## File map

| File | Responsibility |
| --- | --- |
| `lib/jmespath/cli/failure_diagnostic.rb` | Private failure messages, metadata validation, and source adaptation |
| `sig/internal/cli_failure_diagnostic.rbs` | Private formatter declarations |
| `lib/jmespath/cli.rb` | Require formatter, route failures, and explain diagnostics in help |
| `spec/integration/cli_spec.rb` | Public CLI behavior, injected errors, and both executables |
| `docs/guides/errors.md` | CLI examples, fallbacks, and JSON failure policy |

### Task 1: Render located query failures

**Interfaces:**

- Consume `JMESPath::Diagnostic.format(error: Errors::SyntaxError) -> String` unchanged.
- Add internal `CLI::FailureDiagnostic.format(error, expression) -> String`, marked `@api private`.
- Accept `Errors::Error | JSON::ParserError | IOError | SystemCallError` and `String?` expression arguments.
- Add private `message(error) -> String`, `type_message(error) -> String`, and `arity_message(error) -> String`.
- Add private `type_name(type: Symbol) -> String` and `source_position(error, expression) -> Integer?`.
- Return UTF-8 without a trailing newline; `CLI.run` owns stderr output and status 1.

- [x] **Step 1: Add failing CLI examples for query diagnostics.**

Replace the previous type-message assertion with this literal expectation:

```ruby
expect(cli(["length(@)"], "4")).to eq([
  1, "",
  "Invalid argument 1 for length: expected string, array, or object; received number " \
  "at line 1, column 1\nlength(@)\n^\n"
])
```

Assert `items[` produces `Expected an array index at line 1, column 7\nitems[\n      ^\n`.
Assert `length()` reports `Invalid number of arguments for length: expected 1; received 0` before its location.
Assert `merge()` reports `Invalid number of arguments for merge: expected at least 1; received 0`.
Assert `join(',', @)` with input `[1]` expects `array of strings` and reports actual `array`.
Assert `sum(@)` with input `["x"]` expects `array of numbers`.
Assert `sort_by(@, &key)` with input `[{"key":true}]` reports an invalid expression result for argument 2.
Use `Invalid expression result for argument 2 of sort_by: expected number or string; received boolean`.
Assert inner `reverse` failure starts at column 8 in `length(reverse(@))`.
Assert `['✓', length(@)]` locates `length` at character column 7 despite its byte offset of 8.
Add multiline positional queries, tabs, and escaped control characters with literal excerpts and caret indentation.
Keep unknown-function suggestions and `[::0]` message-only output under exact assertions.

- [x] **Step 2: Add metadata fallback examples through `CLI.run`.**

Stub `JMESPath.search` to raise manually constructed type and arity errors.
Assert absent validation fields retain the escaped original message.
Assert absent source ranges omit coordinates; complete messages still render without locations.
Assert incomplete validation fields retain coordinates when the source range is usable.
Cover nil validation stage, empty expected types, nil actual type, and nil variadic metadata as message fallbacks.
Cover exact, minimum, and zero arity counts without truthiness mistakes.
For `['✓', length(@)]`, reject negative, reversed, empty, inclusive, out-of-bounds, and character-splitting ranges.
Validate both range endpoints; a valid start with an invalid finish must omit location.
Exercise invalid source encoding and verify reason-only UTF-8 output.
Assert formatting preserves exception metadata and message across repeated runs.

- [x] **Step 3: Run regression tests before implementation.**

Run `bundle exec rspec spec/integration/cli_spec.rb`.
Expect failures for missing excerpts and structured details, with valid test setup.

- [x] **Step 4: Implement the formatter and CLI routing.**

Require the private formatter after loading `jmespath` in `cli.rb`.
Pass syntax errors directly to the public formatter.
Build type and arity messages from complete metadata; use original messages for incomplete metadata.
Render `:array_string` as `array of strings` and `:array_number` as `array of numbers`.
Join two accepted types with `or`; use commas and final `, or` for longer lists.
Accept positive argument positions and nonnegative arity counts; require a known validation stage for type details.
Require known `variadic?` metadata before choosing exact or minimum arity wording.
Validate exclusive, nonempty source ranges against the original expression and both character boundaries.
Use a temporary `SyntaxError` with the rendered reason, original expression, and validated start offset.
For message-only diagnostics, omit its position so the public formatter escapes controls without inventing coordinates.
Keep helper bodies private and add matching private RBS declarations.
Route rescued expected failures through `.format(e, argv.first)` without widening rescue classes.

- [x] **Step 5: Verify query diagnostics and commit.**

Run `bundle exec rspec spec/integration/cli_spec.rb spec/unit/diagnostic_spec.rb`.
Run `bundle exec rake types`.
Require all examples and type checks to pass.
Commit only Task 1 files with `feat(cli): render located query diagnostics`.

### Task 2: Verify input handling and executable contracts

**Interfaces:** Consume Task 1's formatter through unchanged `CLI.run` and both repository executables.

- [x] **Step 1: Add failing tests for generic JSON errors and help.**

```ruby
expect(cli(["@"], '{"private_marker":BROKEN}'))
  .to eq([1, "", "Invalid JSON input\n"])
expect(cli(["--help"], "invalid")[1])
  .to include("Query failures include source locations when available.")
```

Add stream errors with control characters; assert escaped messages and status 1.
Use an input double that rejects `read` for help, version, missing arguments, and excess arguments.
Assert usage stderr remains exact, with empty stdout and status 2.
Assert an unrelated `ArgumentError` or `RuntimeError` raised during search propagates unchanged.
Assert malformed JSON takes precedence over invalid query syntax, preserving parsing order.
For each executable, run syntax, type, arity, unknown-function, invalid-value, malformed-JSON, and usage cases through `Open3.capture3`.
Assert exact exit status, empty stdout, expected stderr, and absence of ANSI escapes and backtraces.
Retain successful Unicode JSON output coverage for both executable names.

- [x] **Step 2: Confirm failures before changing input diagnostics.**

Run `bundle exec rspec spec/integration/cli_spec.rb`.
Expect generic-JSON and help assertions to fail; query diagnostics from Task 1 must pass.

- [x] **Step 3: Implement JSON policy and documentation.**

Return `Invalid JSON input` from the formatter for `JSON::ParserError` without inspecting its message.
Add `Query failures include source locations when available.` to CLI help.
Keep the validation and suggestion help sentences.
Update the errors guide's statement that formatting leaves CLI output unchanged.
Document runtime carets, expression-result details, metadata fallbacks, Unicode alignment limits, and generic JSON failures.
Include shell examples showing stdin JSON, stderr diagnostics, and status 1.
Preserve the public syntax formatter's accepted error type and executable Ruby examples.

- [x] **Step 4: Verify the complete change.**

Run `bundle exec rake` and require all checks, including 100% line and branch coverage, to pass.
Run `bundle exec rake docs` and require successful documentation generation.
Run the installed repository prose checker on the touched guide, spec, and plan.
Run `git diff --check` and review the diff for unrelated changes or public API expansion.

- [x] **Step 5: Commit and report verified behavior.**

Commit only Task 2 files with `feat(cli): protect input diagnostics and document failures`.
Report the verification results and show `bundle exec ruby exe/jmespath 'length(@)'` with stdin JSON `4`.
Keep remote publication and pull request creation outside this plan.

## Verification record

Implemented on `feat/cli-diagnostics` using native execution.
Task 1 regressions failed on missing excerpts and structured messages before implementation.
Task 2 regressions failed on parser-message disclosure and missing help before implementation.
`bundle exec rake` passed 4,208 examples with 100% line and branch coverage, lint, types, complexity, and documentation checks.
`bundle exec rake docs` completed with 100% of public items documented.
Prose and whitespace checks passed.
Both executable names passed success, syntax, type, arity, suggestion, invalid-value, malformed-JSON, and usage cases.
