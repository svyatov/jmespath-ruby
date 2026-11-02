# CLI JSON Lines input implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add incremental `--json-lines` input to both executables with one compilation and contextual failures.

**Architecture:** Add a private execution path to `JMESPath::CLI`. Compile before input access, then parse, evaluate, and serialize each physical line before reading another. Reuse `CLI::FailureDiagnostic` behind an input-line prefix.

**Tech stack:** Ruby 3.3+, JSON, OptionParser, RSpec, RBS, Steep, and the locked development bundle.

**Spec:** [Approved JSON Lines design](../specs/2026-11-02-cli-json-lines-design.md).

## Global constraints

- Preserve default document processing, standard JMESPath semantics, and readable query diagnostics.
- Exclude parallel evaluation, multiline records, automatic format detection, recovery after failures, dependencies, and unrelated CLI refactoring.
- Keep the output protocol limited to `puts`.
- Retain support for read-only injected streams in document mode.
- Preserve imported compliance fixtures and unrelated `oss-audit-report.md` work.
- Use focused regression tests before implementation; require 100% line and branch coverage through the full gate.
- Raw output has an approved design but no implementation at this plan's baseline, commit `b71e638`.
- Preserve raw-output work if it arrives before execution; add its JSON Lines conflict without implementing raw output here.

## Review focus

- R1: Read or write failures after successful records preserve output and identify the active input line.
- R2: A query-file error or invalid query wins over a missing document file, without a record prefix.
- R3: A reader with only `gets` supports JSON Lines; a reader with only `read` still supports document mode.
- R4: Unicode and multiline query diagnostics retain query coordinates separately from the input line number.
- R5: Option conflicts exit while stdin remains open and unread, including through both executables.

## File map

| File | Responsibility |
| --- | --- |
| `lib/jmespath/cli.rb` | Flag parsing, compile-before-input dispatch, line iteration, and contextual failures |
| `sig/internal/cli.rbs` | Private helper signatures and the extended argument tuple |
| `sig/jmespath.rbs` | Mode-specific input protocols accepted by `CLI.run` |
| `spec/integration/cli_json_lines_spec.rb` | Regression, stream, diagnostic, file-lifetime, and executable tests |
| `spec/integration/cli{,_file,_query_file,_pretty}_spec.rb` | Literal usage expectations and default-mode regressions |
| `README.md`, `docs/guides/errors.md` | Usage, stream requirements, partial output, memory behavior, and diagnostic examples |

If raw output lands first, include its CLI spec in usage updates and focused checks.
Keep both executable wrappers and `CLI::FailureDiagnostic` unchanged unless a regression proves a required change.

### Task 1: Implement and verify JSON Lines processing

**Interfaces:** Preserve `CLI.run(argv, stdin:, stdout:, stderr:) -> Integer` and the writer's `puts(String)` protocol. Add `_LineReader#gets() -> String?` alongside `_Reader#read() -> String?`, with `CLI.run` accepting either protocol. Document that the selected mode determines the required method.

Extend `parse_arguments(Array[String])` from five fields to six, appending `json_lines: bool` after `pretty`. If raw output already exists, append after its flag instead. Preserve the tuple's other fields and single-query shortcut.

Add private `execute_lines(expression: String, path: String?, stdin: _LineReader, stdout: _Writer, stderr: _Writer) -> Integer`. It compiles once, then opens a UTF-8 document file or selects stdin.

Add private `process_lines(compiled: Expression, expression: String, input: _LineReader, output: _Writer, errors: _Writer) -> Integer`. It owns the active line number and handles record failures with the standard exception set. Keep mode-specific RBS assertions at dispatch boundaries where Steep needs narrowing.

- [ ] **Step 1: Verify the CLI baseline.**

Run `bundle exec rspec spec/integration/cli_spec.rb spec/integration/cli_file_spec.rb spec/integration/cli_query_file_spec.rb spec/integration/cli_pretty_spec.rb`. Require zero failures before adding tests. Recheck branch state and raw-output implementation before editing.

- [ ] **Step 2: Add output and query-preparation regression tests.**

Create `spec/integration/cli_json_lines_spec.rb` with the UTF-8 StringIO helper and temporary-directory pattern from `cli_pretty_spec.rb`. Include these exact assertions:

```ruby
expect(run_cli(["--json-lines", "user.name"],
               input: StringIO.new("{\"user\":{\"name\":\"café\"}}\n{}\n{\"user\":{\"name\":false}}")))
  .to eq([0, "\"café\"\nnull\nfalse\n", ""])
expect(run_cli(["--json-lines", "@"], input: StringIO.new(""))).to eq([0, "", ""])
expect(run_cli(["--json-lines", "items["], input: double("unused stdin")))
  .to eq([1, "", "Expected an array index at line 1, column 7\nitems[\n      ^\n"])
```

Test `@` with objects, arrays, strings, integers, floats, booleans, and null in one stream. Assert exact compact JSON with LF output for LF and CRLF input. Verify a final unterminated line and rejection of pretty-printed multiline records.

Spy on `JMESPath.compile` with `and_call_original`; assert one call for several records and one for empty input. Reject invalid syntax before document opening. For R2, test invalid query text plus a missing document, and a missing query file plus a missing document. Assert no `Input line` prefix.

- [ ] **Step 3: Add parsing, diagnostic, and termination regressions.**

For query `@`, feed `1\nBROKEN\n2\n`; assert `[1, "1\n", "Input line 2:\nInvalid JSON input\n"]`. Repeat with a blank line and a whitespace-only line, including malformed JSON containing `private_marker`; assert no document fragments leak.

For `length(@)`, feed `[]\n4\n[]\n`; assert output `0\n` and this exact stderr:

```text
Input line 2:
Invalid argument 1 for length: expected string, array, or object; received number at line 1, column 1
length(@)
^
```

For R4, use a saved query `['✓',\n length(@)]\n` and input `[]\n4\n`. Assert prior output `["✓",0]\n`, `Input line 2:`, and the type diagnostic at query line 2, column 2 with the excerpt and caret. Cover arity, unknown-function, and invalid-value failures with the same contextual prefix and no failed-record output. Assert unrelated RuntimeError and ArgumentError propagate unchanged.

- [ ] **Step 4: Add incremental-reader and stream-ownership regressions.**

For R3, provide a reader implementing only `gets`, returning `1\n`, `2\n`, then nil. Use an ordered spy to assert `gets`, `puts("1")`, `gets`, `puts("2")`, then the EOF read. Make whole-stream `read` unavailable. On malformed or invalid-type record 2, assert record 3 is never requested. Separately retain a document-mode reader implementing only `read`.

For R1, raise IOError from the second `gets`; assert retained `1\n`, status 1, and `Input line 2:`. Raise IOError from the second output `puts` before it writes; assert the same retained output and line number. Cover a closed stdin and handled SystemCallError. Use the ordinary renderer's escaping behavior for error text.

Observe files opened by the CLI and assert closure after success, parse failure, evaluation failure, and read failure. Assert selected file input leaves stdin unused. Assert caller-owned input and output streams remain open after success and failure.

- [ ] **Step 5: Add option and executable regressions.**

Cover flags before and after queries, both query sources, stdin and file sources, equals paths, literal `-`, spaces, option-like paths, delimiters, POSIXLY_CORRECT, and frozen unchanged arguments. Update literal usage expectations to include `[--pretty | --json-lines]`, retaining the separate validation line. Include raw output in that exclusive group only if implemented.

Reject repeated flags, `--json-lines=true`, abbreviations, short aliases, missing or excess queries, and conflicts with pretty formatting or validation in both orders. Assert status 2, empty stdout, exact usage, and no file or stdin access. Test raw-output conflicts as unsupported options until that flag exists, then as explicit mode conflicts. Preserve literal `--validate --json-lines` query validation.

For both executable names, assert successful multiple records, file input, saved queries, empty input, invalid-query failure, and retained output after a later parse or evaluation failure. For R5, use the `Open3.popen3` timeout and cleanup pattern to prove validation conflicts exit before stdin closes.

- [ ] **Step 6: Run the new tests and confirm feature failures.**

Run `bundle exec rspec spec/integration/cli_json_lines_spec.rb`. Confirm failures arise from unsupported JSON Lines behavior, then implement the feature.

- [ ] **Step 7: Add the minimal CLI execution path and signatures.**

Register `json-lines` as a boolean flag with repetition rejection. Reject conflicts in `check_sources` before query loading. Extend validation restrictions while preserving the exact two-argument dispatch.

After query loading and validation dispatch, select `execute_lines` when requested; preserve ordinary `execute` otherwise. Compile before opening the document stream. Scope CLI-owned files with `File.open(path, "r:UTF-8")` blocks.

In `process_lines`, increment the active line number before each `gets` attempt. For each returned line, parse, evaluate through `compiled.search`, serialize, then call `puts`. On handled failures, print `Input line N:` followed by `FailureDiagnostic.format(error, expression)`, and return 1. On EOF, return 0. Keep compilation and file-open failures in `CLI.run`'s ordinary rescue.

Update RBS for the new protocol, argument tuple, and helpers. Update YARD to describe mode-specific injected streams. Retain read-only document readers without requiring `gets` globally.

- [ ] **Step 8: Verify focused behavior and type correctness.**

Run the baseline CLI specs plus `spec/integration/cli_json_lines_spec.rb`; require zero failures. Run `bundle exec rake types`; require successful RBS validation and Steep checks. Address only failures caused by this change.

- [ ] **Step 9: Document the feature and run full checks.**

Add help, README, and errors-guide examples for `jmespath --json-lines 'user.name' < events.jsonl` and file input. Explain empty input, compilation before input, rejected blank lines, mode conflicts, partial output, memory proportional to the current record and result, and normal buffering. Describe injected-stream requirements and line-prefixed query diagnostics. Preserve default document-mode documentation.

Run `env RUBOCOP_CACHE_ROOT=/private/tmp/jmespath-rubocop-cache bundle exec rake` and `bundle exec rake docs`. Require zero failures, full line and branch coverage, and successful documentation generation. Run the oss-writing prose checker on the touched prose and `git diff --check`.

- [ ] **Step 10: Commit the verified feature.**

Stage only the implementation, signatures, tests, and documentation listed above. Commit as `feat(cli): evaluate JSON Lines incrementally`. Keep remote operations and release work outside this plan.

## Self-review

The single task covers each approved requirement, including all five review-focus cases. Its tests precede implementation and preserve default-mode compatibility. No dependency installation, public expression API change, executable wrapper change, or imported fixture edit is required.
