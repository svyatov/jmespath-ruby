# CLI function listing implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide `--functions` as a readable reference for built-in names, signatures, and descriptions through both executables.

**Architecture:** Dispatch standalone listing through the CLI's information path after literal validation handling. A private formatter consumes public metadata. Reject combined listing requests through argument parsing before input access.

**Tech Stack:** Ruby 3.3+, RSpec, RBS, Steep, YARD, and standard library dependencies already used by the repository.

**Spec:** [Approved design](../specs/2026-11-02-cli-functions-design.md).

## Global constraints

Preserve default query behavior, standard JMESPath semantics, and the public Ruby API.
Use public `Functions#names` and `Functions#metadata` without accessing registry internals or executing functions.
Exclude custom registries, return types, machine-readable output modes, shell completion, dependencies, and unrelated CLI refactoring.
Preserve imported compliance fixtures and unrelated `oss-audit-report.md` changes.
Leave caller-owned streams and `argv` unchanged.

## Review focus

R1: Flag-looking filenames remain literal path values, even when named `--functions`.
R2: The delimiter preserves `--functions` as query text; quoted identifiers with that name still query documents.
R3: Literal validation takes precedence for `--validate --functions`, which validates query text rather than listing functions.
R4: Output failures return status 1 through ordinary diagnostics; unrelated exceptions propagate.
R5: Every metadata type renders correctly, including repeated unions and zero-argument signatures absent from built-ins.

## File responsibilities

| Files | Responsibility |
| --- | --- |
| Create `lib/jmespath/cli/function_listing.rb` | Render signatures, descriptions, and the exact legend |
| Modify `lib/jmespath/cli.rb` | Load formatter, dispatch listing, extend usage and help |
| Modify `lib/jmespath/cli/arguments.rb` | Reject listing in parsed combinations |
| Modify `sig/internal/cli.rbs` | Declare private formatter interfaces |
| Create `spec/integration/cli_functions_spec.rb` | Verify listing, isolation, conflicts, and both executables |
| Create `spec/unit/cli_function_listing_spec.rb` | Verify synthetic metadata and exact formatting |
| Modify `spec/integration/cli_spec.rb`, `cli_file_spec.rb`, `cli_query_file_spec.rb`, `cli_pretty_spec.rb`, `cli_raw_output_spec.rb`, and `cli_json_lines_spec.rb` in that directory | Extend literal usage expectations |
| Modify `README.md` and `docs/guides/functions.md` | Document standalone listing and notation |

## Task 1: Deliver the standalone function reference

**Interfaces:**

Consume `Functions.default`, `Functions#names -> Array[String]`, and `Functions#metadata(String) -> Functions::Metadata?`.
Produce private `CLI::FunctionListing.render(Functions) -> String`, ending in exactly one newline.
Use private singleton helpers `signature(Functions::Metadata) -> String`, `argument(Array[Symbol], bool) -> String`, and `type_name(Symbol) -> String`.
Keep `CLI.run` and argument parser return types unchanged.

- [ ] **Step 1: Add failing listing and formatter examples.**

In `cli_functions_spec.rb`, use `run_cli(arguments, input:, output:)` returning `[status, stdout_text, stderr_text]`.
Supply stdin with `read` and `gets` methods that raise on access.
Assert status 0, empty stderr, unchanged frozen arguments, and open caller streams.
Reject file opening, query compilation, evaluation, and registry calls with mocks that raise on invocation.
Split listing entries from the legend at the blank line.
Assert entry names equal `Functions.default.names`, without duplicates.
Assert each description matches metadata and independently reconstruct argument types from metadata in the test.
Independently assert these complete lines:

```ruby
expect(entries).to include(
  "join(string, array<string>) Join strings with a separator.",
  "length(string|array|object) Character or element count.",
  "map(expref, array) Map an expression over an array, including null results.",
  "merge(object...) Merge objects, with later values winning.",
  "sort(array<number>|array<string>) Stable sorted array of numbers or strings."
)
```

Assert the exact five-line legend from the spec and the final newline.
In `cli_function_listing_spec.rb`, create immutable synthetic registries for R5 with callbacks that raise.
Assert `zero() Zero.`, `sample((string|null)...) Sample.`, and `sample(boolean, array<number>, any...) Sample.` independently.
Check an empty registry renders the blank separator and legend without invoking callbacks.

- [ ] **Step 2: Run the examples and confirm missing-feature failures.**

Run `bundle exec rspec spec/integration/cli_functions_spec.rb spec/unit/cli_function_listing_spec.rb`.
Expect failures because standalone listing and its formatter are absent.

- [ ] **Step 3: Implement the formatter and standalone dispatch.**

Create the private formatter module and its declared methods in `lib/jmespath/cli/function_listing.rb`.
Render signatures and descriptions exactly as the spec defines, followed by the exact legend.
Require the formatter from `cli.rb`.
Recognize standalone `--functions` alongside standalone help and version after `literal_validation?`.
Have `information(argv, output)` write the rendered listing and return 0 for that request.
Register `--functions` with the parser's rejected information combinations, leaving parsing tuples unchanged.
Append `jmespath --functions` as a third usage line with seven leading spaces.
Explain standalone listing, unread stdin, notation, conflicts, and listing statuses in help.
Update module YARD descriptions and private RBS declarations for the formatter and helpers.
Extend every literal usage expectation identified in the file map, including the embedded subprocess expectation in `cli_spec.rb`.

- [ ] **Step 4: Add conflict, compatibility, and output-failure regressions.**

Assert `[2, "", usage]` for repeated flags, values, abbreviations, positional queries, and conflicts with every supported mode or information flag.
Test both orders of each conflict, except the exact two-argument literal validation form.
Include `--file`, `--query-file`, equals paths, missing paths, `--validate`, `--pretty`, `--raw-output`, and `--json-lines`.
Reject every invalid combination before input access, with frozen arguments preserved.
For R1, use files named `--functions` as values of `--file` and `--query-file`, including equals syntax.
For R2, assert `-- --functions` produces the ordinary query diagnostic with valid JSON input.
Also assert a quoted identifier queries a document key named `--functions` successfully.
For R3, assert `[1, "", "Expected a digit at line 1, column 1\n--functions\n^\n"]` for literal validation.
For R4, make stdout raise `IOError, "write failed"`; assert status 1 and `"write failed\n"` on stderr.
Also assert an unrelated `RuntimeError` from stdout propagates unchanged.
Assert help includes listing usage and notation while help and version retain their standalone behavior.

- [ ] **Step 5: Add subprocess checks and run all CLI examples.**

Use `Open3.popen3` and `Timeout.timeout(5)` with the cleanup pattern in `cli_json_lines_spec.rb`.
For both executable names, verify listing finishes with status 0 while stdin stays open.
Compare subprocess output with the verified formatter and assert empty stderr.
For both executable names, verify a conflicting request finishes with `[2, "", usage]` while stdin stays open.
Run `bundle exec rspec spec/integration/cli_functions_spec.rb spec/unit/cli_function_listing_spec.rb spec/integration/cli_spec.rb spec/integration/cli_file_spec.rb spec/integration/cli_query_file_spec.rb spec/integration/cli_pretty_spec.rb spec/integration/cli_raw_output_spec.rb spec/integration/cli_json_lines_spec.rb`.
Expect zero failures.

- [ ] **Step 6: Document the feature.**

Add standalone `jmespath --functions` examples to the README and functions guide.
Explain unions, homogeneous arrays, expression references, required variadic arguments, and narrower runtime checks.
State the conflict rules, literal validation exception, and that listing leaves stdin unread.
Keep shell completion scoped to issue #27.

- [ ] **Step 7: Run required checks and verify actual CLI behavior.**

Run `env RUBOCOP_CACHE_ROOT=/private/tmp/jmespath-rubocop-cache bundle exec rake`.
Expect all checks to pass, including 100% line and branch coverage.
Run `bundle exec rake docs` and expect success.
Run both executables with standalone `--functions` and confirm the documented entries and legend.
Run the prose checker on changed documentation and `git diff --check`; expect zero findings.
Review the diff against every spec requirement, including R1 through R5.

- [ ] **Step 8: Commit the verified feature.**

Stage only task files and completed plan checkboxes.
Commit with `feat(cli): list built-in functions and signatures`.
Report verification evidence and preserve separate authorization for remote operations.
