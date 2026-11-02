# CLI query files implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute and syntax-validate saved UTF-8 queries through `--query-file PATH` in both executables.

**Architecture:** Extend the exact-match OptionParser and retain the positional validation handler. Read query files before document input, then reuse search and diagnostic rendering. Preserve document-before-query-compilation ordering for execution.

**Tech Stack:** Ruby 3.3+, OptionParser, JSON, RSpec, RBS, Steep, and YARD.

**Spec:** [Approved design](../specs/2026-11-02-cli-query-file-design.md).

## Global constraints

- Require exactly one query source: one positional expression or one query file.
- Reject usage failures before opening files or reading stdin.
- Preserve the exact two-argument form `--validate EXPRESSION`, including expressions that resemble flags.
- Reject document options in validation mode.
- Preserve caller ownership of `argv` and stdin.
- Do not catch unrelated application exceptions.
- Preserve imported compliance fixtures and public Ruby signatures.
- Exclude includes, templates, substitution, multiple queries, additional dependencies, and unrelated CLI refactoring.
- Preserve the unrelated untracked `oss-audit-report.md`.

## Review focus

- R1: CRLF query files must retain their bytes, source offsets, and diagnostic coordinates.
- R2: A delimiter must prevent a following `--validate` token from becoming a mode option.
- R3: Frozen argument arrays and `POSIXLY_CORRECT` must preserve supported option order and caller arguments.
- R4: Query read failures must close owned files before returning or propagating unrelated exceptions.
- R5: A malformed document must retain precedence over syntax or encoding failures in a readable query file.

## File map

| File | Responsibility |
| --- | --- |
| `lib/jmespath/cli.rb` | Query source options, file reading, validation dispatch, usage, help, and YARD |
| `sig/internal/cli.rbs` | Private helper signatures |
| `spec/integration/cli_query_file_spec.rb` | Query files, diagnostics, ownership, validation, and executable tests |
| `spec/integration/cli_spec.rb` | Literal usage expectations and positional compatibility |
| `spec/integration/cli_file_spec.rb` | Literal usage expectations and document mode compatibility |
| `README.md` | Query-file execution and validation examples |
| `docs/guides/errors.md` | File failures, unchanged source coordinates, and validation precedence |

### Task 1: Add query files to execution and syntax validation

**Interfaces:**

- Preserve public `CLI.run(argv, stdin:, stdout:, stderr:) -> Integer`.
- Extend private `CLI.parse_arguments(argv: Array[String]) -> [String?, String?, String?, bool]`.
- Return positional expression, document path, query path, and syntax-validation mode in that order.
- Add private `CLI.read_query(expression: String?, path: String?) -> String` to select and read the validated query source.
- Retain `CLI.validation(argv: Array[String], errors: _Writer) -> Integer` for legacy positional syntax validation.
- Reuse `CLI.read_document(path, stdin)` and `CLI::FailureDiagnostic.format(error, expression)` without public changes.

- [ ] **Step 1: Add failing argument and success regressions.**

Create the query-file spec with temporary UTF-8 files and a helper returning `[status, stdout, stderr]`.
Use an input double that rejects access when stdin must remain unused.
With query `user.name\n` and JSON `{"user":{"name":"café"}}`, assert:

```ruby
expect(run_cli(["--query-file", query_path], input: StringIO.new(document)))
  .to eq([0, "\"café\"\n", ""])
expect(run_cli(["--query-file", query_path, "--file", document_path]))
  .to eq([0, "\"café\"\n", ""])
expect(run_cli(["--validate", "--query-file", query_path]))
  .to eq([0, "", ""])
expect(run_cli(["--query-file", query_path, "--validate"]))
  .to eq([0, "", ""])
```

Cover both file-option orders, equals values, quoted spaces, option-like paths, literal `-`, and a final delimiter.
Assert usage status 2 with empty stdout for missing sources, extra expressions, conflicts, repeated options, and missing values.
Cover unknown options, option abbreviations, help/version combinations, and validation combined with `--file`.
For usage cases, make file opens and stdin access fail if attempted.
Pin R2 with `--query-file PATH -- --validate`, which is a conflicting positional source and must return status 2.
Pin R3 using frozen arrays and restored `POSIXLY_CORRECT=1` for successful and rejected forms.
Retain `--validate --help` as a syntax failure and `--validate --query-file` as literal query text, both status 1.
Require validation of `unknown()` and `length()` from files to succeed without document input.

- [ ] **Step 2: Add failing source, diagnostic, and ownership regressions.**

Use query `['✓',\n length(@)]\n` with JSON `4`.
Expect status 1, empty stdout, the existing type message at line 2, column 2, excerpt ` length(@)]`, and one space before `^`.
Use the same layout with `length()` to verify the complete arity diagnostic.
Use query `['✓',\n items[\n` to assert a syntax failure at line 3, column 1, with an empty excerpt and caret.
Verify these exact diagnostics in execution and syntax validation where applicable, with stdin and document files.
Test empty queries, trailing newlines, Unicode preceding a same-line failure, invalid UTF-8, and unknown-function suggestions.
For invalid UTF-8 with valid JSON, expect `[1, "", "Expression has invalid encoding\n"]`.
Pin R1 by observing the exact query string passed to search and validation, including CRLF bytes.
Pin R5 with invalid query text and malformed JSON containing a private marker: expect only `Invalid JSON input\n`.
Verify missing paths and simulated permission failures return status 1, escaped stderr, and empty stdout.
Use a path containing newline and escape characters to verify terminal-safe diagnostics.
Assert query-file failures never read stdin or open the document path.
Pin R4 with actual owned file objects and injected `IOError`, `Errno::EIO`, and unrelated `RuntimeError` from reads.
Assert closure after success and failure, and exception identity for unrelated errors.
Verify query files close before document access and validation or evaluation starts.

- [ ] **Step 3: Confirm the regressions fail for missing query-file support.**

Run `bundle exec rspec spec/integration/cli_query_file_spec.rb spec/integration/cli_spec.rb spec/integration/cli_file_spec.rb`.
Require the new feature tests to fail for absent support, while baseline positional and document-file tests pass.

- [ ] **Step 4: Extend the parser and query reading.**

Keep the exact two-argument `--validate EXPRESSION` dispatch ahead of option parsing.
Register `--query-file PATH` and `--validate` in the exact-match parser, preserving nonmutating option permutation.
Reject repeated flags, conflicting sources, invalid validation/document combinations, and unsupported informational combinations before input access.
Preserve the positional expression fast path, including invalid-encoding behavior; extend its tuple to the declared interface.
Read query files with block ownership and UTF-8 encoding, preserving bytes and avoiding newline conversion on supported platforms.
Keep an expression local available to diagnostics after reading the query.
For parsed validation mode, reuse the positional validation handler with the resolved source and return before document reading.
For execution, resolve the source, read JSON, and call search in that order.
Retain expected-error handling and propagate unrelated exceptions.
Update private RBS declarations and CLI YARD comments to match these interfaces.
Update usage and all literal usage expectations for query-file execution and validation.

- [ ] **Step 5: Add executable regressions and documentation.**

Exercise both `exe/jmespath` and `exe/jmespath.rb` through `Open3`.
Cover Unicode success with stdin, success with `--file`, multiline syntax/type/arity diagnostics, missing queries, and source conflicts.
Use an open stdin pipe with a timeout to prove file validation and missing-query-file failures finish without consuming document input.
Ensure timed-out subprocesses are terminated and reaped.
Assert exit status, exact stderr, and empty stdout on every expected failure.
Update help, README examples, and the errors guide for both query sources, literal paths, and syntax-only file validation.
Explain the legacy two-argument validation precedence and query-read-before-document ordering.

- [ ] **Step 6: Verify the complete feature.**

Run the three CLI spec files and require zero failures.
Run `bundle exec rake` and require lint, types, full tests, coverage, complexity, and documentation checks to pass.
Run `bundle exec rake docs` and require successful YARD generation.
Run `bundle exec rake package:check` and require both packaged executables to pass the offline installation checks.
Run the installed prose checker on touched Markdown and require zero findings.
Run `git diff --check` and inspect the feature diff against the approved design.

- [ ] **Step 7: Commit the feature.**

Stage only the task's files and commit with `feat(cli): read queries from files`.
Record the actual verification results in this plan and preserve unrelated work.
Leave remote operations and publication outside this plan.
