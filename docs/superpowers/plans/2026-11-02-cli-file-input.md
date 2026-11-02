# Explicit JSON file input implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read one UTF-8 JSON file through `--file PATH`, retaining stdin input and CLI diagnostics.

**Architecture:** Use standard-library `OptionParser` inside the shared CLI runner. Parse arguments before accessing input, then read and parse CLI-owned files inside a closing block. Pass the parsed expression to the diagnostic renderer.

**Tech Stack:** Ruby 3.3+, OptionParser, JSON, RSpec, RBS, Steep, and YARD.

**Spec:** [Approved design](../specs/2026-11-02-cli-file-input-design.md).

## Global constraints

- No gem dependencies are added.
- Omitting `--file` selects stdin.
- The user selected literal path handling: `--file -` reads a file named `-`.
- Reject usage failures before reading stdin or opening files.
- Preserve standalone `--help`, `-h`, and `--version` with status 0 and no input access.
- Keep compact JSON output and the document-before-query evaluation order.
- Do not catch unrelated application exceptions.
- Keep the Ruby search API, standard JMESPath semantics, and imported compliance fixtures unchanged.
- File failures must not silently fall back to stdin.
- Exclude multiple input files, directory traversal, positional filename inference, and additional input or output modes.
- Preserve the unrelated untracked `oss-audit-report.md`.

## Review focus

- R1: Environment settings must not disable options following a query; test with `POSIXLY_CORRECT` set.
- R2: Frozen caller arguments must remain unchanged; pass a frozen array and compare its contents after success and failure.
- R3: An empty expression must reach query validation after document parsing; expect status 1 rather than usage status 2.
- R4: File paths containing control characters must produce escaped stderr without terminal controls or extra diagnostic lines.
- R5: Unexpected evaluation errors must propagate after the owned file closes; inject a specific `RuntimeError` instance.

## File map

| File | Responsibility |
| --- | --- |
| `lib/jmespath/cli.rb` | Option parsing, file ownership, diagnostic expression, usage, help, and YARD |
| `sig/internal/cli.rbs` | Private helper declarations |
| `Steepfile` | Load the standard-library OptionParser signatures |
| `spec/integration/cli_file_spec.rb` | File input, argument rules, ownership, and both executable names |
| `spec/integration/cli_spec.rb` | Update literal usage expectations while preserving stdin and diagnostic regressions |
| `README.md` | File selection and shell argument examples |
| `docs/guides/errors.md` | File read failures and diagnostic behavior |

### Task 1: Add explicit document files with diagnostic integration

**Interfaces:**

- Preserve `CLI.run(argv, stdin:, stdout:, stderr:) -> Integer` and the public `_Reader` and `_Writer` protocols.
- Add internal `CLI.parse_arguments(argv: Array[String]) -> [String, String?]`, returning expression and optional path.
- Raise `OptionParser::ParseError` subclasses for invalid arguments; `CLI.run` prints usage to stderr and returns 2.
- Add internal `CLI.read_document(path: String?, stdin: _Reader) -> JMESPath::value` for JSON parsing and file ownership.
- Reuse `CLI::FailureDiagnostic.format(error, expression: String?) -> String` without changing its positional Ruby arguments.
- Preserve `CLI.information(argv, output) -> Integer` for standalone informational calls.
- Mark added helpers `@api private` and declare them in `sig/internal/cli.rbs`.

- [x] **Step 1: Write failing tests for the public CLI contract.**

Create `spec/integration/cli_file_spec.rb` using real temporary directories and files.
Define `run_cli(arguments, input:)` to return `[status, stdout.string, stderr.string]` through `CLI.run`.
Use `require "tmpdir"`, `StringIO`, and the repository's RSpec setup.
Write a document containing `{"user":{"name":"café"}}` to a UTF-8 file.
Pin successful behavior with these assertions, where `unreadable_input` is a double that rejects every method call:

```ruby
expect(run_cli(["--file", path, "user.name"], input: unreadable_input))
  .to eq([0, "\"café\"\n", ""])
expect(run_cli(["user.name", "--file", path], input: unreadable_input))
  .to eq([0, "\"café\"\n", ""])
```

Repeat success for `--file=PATH`, spaces, option-like filenames using equals or `./`, literal `-`, and the `--` delimiter.
For literal `-`, change directory only inside a restoring block.
Pass closed stdin with a valid file and expect success; verify caller-owned stdin stays open in stdin mode.
Verify R1 using an environment value restored in `ensure`, and R2 using frozen arrays with unchanged contents.
Test unknown options, missing file values, repeated `--file`, missing queries, and extra queries with status 2 and empty stdout.
Test every informational flag alone with status 0; reject each combined with a query or file option with status 2.
For usage and informational cases, make both `File.open` and stdin access fail if called.
Test `--` without a query and arguments following `--` as ordinary positional values.
Test R3 with valid JSON and an empty expression; malformed JSON must still produce `Invalid JSON input\n` first.
Assert the original positional stdin invocation still returns `[0, "2\n", ""]` for `foo.bar` and `{"foo":{"bar":2}}`.

- [x] **Step 2: Write failing tests for file failures and ownership.**

Cover missing paths and `Errno::EACCES`; simulate permissions when the process bypasses filesystem permissions.
Cover `IOError` and `SystemCallError` raised by an opened file's `read` method.
Use actual opened file objects with narrowly scoped wrapping or stubbing to observe `closed?` after each call.
Assert closure after success, malformed JSON, read failures, syntax errors, function errors, and R5's unexpected error.
Assert R5 preserves exception identity and never consumes stdin.
Assert malformed JSON containing `private_marker` returns exactly `[1, "", "Invalid JSON input\n"]`.
Assert an invalid query against malformed JSON reports the JSON error first.
Assert missing and unreadable files return status 1, empty stdout, and escaped operating-system messages.
Test R4 using a path with newline or escape characters; assert the renderer's visible escapes.
Use file JSON `4` and query `length(@)` to require the existing complete type diagnostic and caret.
Use query `length()` to require the complete arity diagnostic and caret.
Use `items[` to require `Expected an array index at line 1, column 7\nitems[\n      ^\n`.
Use `['✓', length(@)]` with JSON `4` to require character column 7 and six spaces before the caret.
Retain unknown-function suggestions and verify all diagnostic cases with file options both before and after the query.

- [x] **Step 3: Confirm regression failures.**

Run `bundle exec rspec spec/integration/cli_file_spec.rb spec/integration/cli_spec.rb`.
Require failures caused by absent file support, with valid test setup and unchanged stdin examples passing.

- [x] **Step 4: Implement option parsing and input ownership.**

Require `optparse` in `lib/jmespath/cli.rb` without changing gem dependencies.
Keep the standalone informational fast path before parsing.
Parse `argv.dup` with explicit permutation so options work after the expression regardless of `POSIXLY_CORRECT`.
Register `--file PATH` without a short alias and reject repeated occurrences.
Reject informational combinations and require exactly one remaining positional expression.
Return the parsed expression and optional file path from `parse_arguments`.
Update usage to `Usage: jmespath [--file PATH] EXPRESSION` and update literal usage expectations in `cli_spec.rb`.
In `read_document`, use `File.open(path, "r:UTF-8")` with a block when a path is supplied.
Read and parse inside that block; close before search starts.
Preserve `JSON.parse(stdin.read.to_s)` when no file is selected.
Keep an optional expression local available to the rescue path before any input operations.
Render expected failures with that expression, preserving the current input and query exception classes.
Handle option errors separately with status 2 and usage on stderr.
Propagate unrelated exceptions without broadening the rescue list.
Update internal RBS declarations and the CLI module's YARD description for both input sources.

- [x] **Step 5: Add executable regression tests and document file input.**

For both executable names, use `Open3.capture3` with a valid UTF-8 file and deliberately invalid stdin.
Assert `[status.exitstatus, output, errors]` equals `[0, "\"café\"\n", ""]`.
Exercise spaces, option-like paths, literal `-`, and options after the query through both executables.
Exercise missing files, malformed file JSON, syntax, type, arity, Unicode carets, and malformed options through both executables.
Require status 1 for input/query failures, status 2 for usage, empty stdout, and expected stderr.
Retain both executables' successful stdin coverage.
Expand CLI help with file input, UTF-8, literal `-`, spaces, option-like filenames, and usage conventions.
Update the README command-line section with the approved shell examples.
Document file errors, closure, and unchanged query diagnostics in the errors guide.
Keep help's validation, suggestion, and source-location descriptions.

- [x] **Step 6: Verify the complete change.**

Run `bundle exec rspec spec/integration/cli_file_spec.rb spec/integration/cli_spec.rb` and require all examples to pass.
Run `bundle exec rake` and require lint, types, tests, coverage, complexity, and documentation checks to pass.
Run `bundle exec rake docs` and require successful documentation generation.
Run `bundle exec rake package:check` to verify packaged CLI assets, including file handling code.
Run the installed prose checker on touched Markdown files and require zero findings.
Run `git diff --check` and review only the task's files for compatibility and unrelated changes.

- [x] **Step 7: Commit the complete feature.**

Stage only files from the file map.
Commit with `feat(cli): read JSON from explicit files` after required checks pass.
Report observed behavior and show `bundle exec ruby exe/jmespath --file document.json 'user.name'` with a matching example document.
Keep remote operations, publication, and unrelated CLI features outside this plan.

## Verification record

Native execution uses `feat/cli-file-input` in the user's selected checkout.
The initial regression run failed 31 file-input examples while all 73 stdin examples passed.
The CLI regression suite passed 121 examples after implementation.
`bundle exec rake` passed 4,257 examples with 100% line and branch coverage, lint, types, complexity, and documentation checks.
`bundle exec rake docs` completed with 100% of public items documented.
`bundle exec rake package:check` verified an offline production-only installation and both executables.
Prose and whitespace checks passed.

The positional-query fast path preserves the invalid-encoding regression that OptionParser rejects before query evaluation.
OptionParser's nonmutating `permute` copies arguments internally and accepts trailing options regardless of `POSIXLY_CORRECT`.
Exact option matching prevents undeclared short aliases; explicit rejection handlers suppress automatic help, version, and completion process exits.
Independent QA passed 158 executable runs plus public-interface ownership and failure probes.
The final independent review found no Critical, Important, or Minor issues and verified R1 through R5.
Runtime verification used Ruby 4.0.9; other Ruby versions and operating systems were not exercised locally.

The reviewer excluded programmatic paths containing NUL bytes because operating-system command-line arguments cannot contain NUL.
These malformed programmatic paths retain Ruby's `ArgumentError`; callers of `CLI.run` must handle that exception themselves.

## Integration verification

Integrated `main` at `c98eb9b` after opening PR #41.
The resolution preserves syntax-only validation dispatch and file-based evaluation, with both forms listed in usage.
The completed inspection, tracing, and validation documents use main's recorded results and clarifications.
A regression verifies validation and document-file options remain separate modes without input access on rejected combinations.

The combined tree passed `bundle exec rake`: 6,301 examples, zero failures, and 100% line and branch coverage.
Lint, types, complexity, documentation checks, YARD generation, and offline package verification passed.
Independent follow-up QA passed 36 observations covering both executables and the affected CLI modes.
