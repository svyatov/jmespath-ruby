# CLI raw string output implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--raw-output` to both CLI executables while preserving JSON defaults, diagnostics, and the output stream protocol.

**Architecture:** Carry one boolean through the exact-match parser into execution. For string results, pass the result plus one newline to `puts`; retain JSON generation for other results.

**Tech Stack:** Ruby 3.3 or later, JSON, OptionParser, RSpec, RBS, and the locked development bundle.

**Spec:** [Approved raw output design](../specs/2026-11-02-cli-raw-output-design.md).

## Global constraints

Preserve default output, standard JMESPath semantics, public Ruby interfaces, and readable diagnostics.
Exclude array joining, NUL delimiters, newline suppression, implicit string conversion, dependencies, and unrelated CLI refactoring.
Preserve imported compliance fixtures and public Ruby signatures.
JSON Lines processing remains outside this change.
Issue #21 owns rejection of raw output combined with JSON Lines processing.

## Review focus

- R1: Empty and newline-terminated strings must receive exactly one additional newline.
- R2: Custom output streams implementing only `puts` must remain usable.
- R3: Conflicts must fail before opening either input file or reading stdin.
- R4: The exact call `--validate --raw-output` must validate literal query text.
- R5: Trailing options under `POSIXLY_CORRECT`, frozen arguments, and the `--` delimiter must retain their behavior.

## File map

| File | Responsibility |
| --- | --- |
| `lib/jmespath/cli.rb` | Parse the flag, reject conflicts, write raw results, and update help |
| `sig/internal/cli.rbs` | Match private tuple and execution signatures |
| `spec/integration/cli_raw_output_spec.rb` | Cover output, arguments, diagnostics, stream compatibility, and both executables |
| `spec/integration/cli_spec.rb` | Update literal usage expectations |
| `spec/integration/cli_file_spec.rb` | Update literal usage expectations |
| `spec/integration/cli_query_file_spec.rb` | Update literal usage expectations |
| `spec/integration/cli_pretty_spec.rb` | Update literal usage expectations and retain conflict coverage |
| `README.md` | Explain raw strings, JSON fallback, newlines, and conflicts |
| `docs/guides/errors.md` | Explain unchanged diagnostics and raw-output conflicts |

### Task 1: Add and verify raw output

**Interfaces:** Preserve `CLI.run(argv, stdin:, stdout:, stderr:) -> Integer` and public `_Reader` and `_Writer` protocols.
Extend private `CLI.parse_arguments(Array[String]) -> [String?, String?, String?, bool, bool, bool]`.
The final booleans are `validate`, `pretty`, and `raw_output`, respectively; all default to false.
Extend private `CLI.execute(expression, path, stdin, stdout, pretty, raw_output) -> Integer` with positional boolean parameters.
Use presence of the string-valued parser hash key `raw-output` to represent the flag.
Keep both executable entry points and other helper signatures unchanged.

- [ ] **Step 1: Verify the CLI baseline.**

Run `bundle exec rspec spec/integration/cli_spec.rb spec/integration/cli_file_spec.rb spec/integration/cli_query_file_spec.rb spec/integration/cli_pretty_spec.rb`.
Require zero failures.

- [ ] **Step 2: Add failing formatting and stream regressions.**

Create `cli_raw_output_spec.rb` using the UTF-8 StringIO helper and temporary files from `cli_pretty_spec.rb`.
Use a `run_cli` helper returning `[status, stdout, stderr]`.
The example `preserves raw string bytes and appends one newline` uses these literal input/output pairs:

```ruby
{
  '""' => "\n", '"café ✓"' => "café ✓\n",
  '"a\"b"' => "a\"b\n", '"a\\\\b"' => "a\\b\n",
  '"a\nb"' => "a\nb\n", '"a\n"' => "a\n\n",
  '"a\n\n"' => "a\n\n\n", '"\n"' => "\n\n"
}.each do |input, expected|
  expect(run_cli(["--raw-output", "@"], input: StringIO.new(input))).to eq([0, expected, ""])
  expect(run_cli(["@"], input: StringIO.new(input))).to eq([0, "#{input}\n", ""])
end
```

The example `retains JSON for non-string results` checks `["a"]`, `{"a":"b"}`, `[]`, `{}`, `42`, `1.5`, `true`, `false`, and `null`.
Assert exact compact input bytes plus one newline for raw and default invocations.
The example `formats the selected result` asserts query `user.name` with `{"user":{"name":"Ada"}}` produces `[0, "Ada\n", ""]`.
The example `supports a puts-only output stream` uses a double with only `puts` and expects the argument `"Ada\n\n"` for a newline-terminated result.

- [ ] **Step 3: Add failing argument and diagnostic regressions.**

Set the literal execution usage line in all CLI specs to `Usage: jmespath [--pretty | --raw-output] [--file PATH] (EXPRESSION | --query-file PATH)`.
Keep the validation usage line unchanged; update both usage literals in `cli_spec.rb`.
Test raw output before and after positional queries, with `--`, with query files, and with both document sources.
Include equals paths and frozen argument arrays; assert their contents remain unchanged.
Test trailing options with `POSIXLY_CORRECT=1` and restore its value in `ensure`.

The example `rejects invalid options before input access` expects `[2, "", usage]` with an unreadable stdin and `File.open` forbidden.
Cover missing queries, extra queries, conflicting query sources, repeats, `--raw-output=true`, `--raw`, `-r`, and help/version combinations.
Cover both orders of pretty/raw and validation/raw conflicts, including query-file and document-file combinations.
Assert `--validate --raw-output` produces `[1, "", "Expected a digit at line 1, column 1\n--raw-output\n^\n"]` without input access.

The example `preserves failure results` compares raw and default invocations against literal diagnostics from `cli_spec.rb`.
Cover malformed JSON, `items[`, `length(@)`, `length()`, `lenght(@)`, and `[::0]`.
Reuse exact multiline syntax and Unicode type diagnostics from `cli_query_file_spec.rb`, with both document sources.
Verify missing query/document files yield status 1, empty stdout, and escaped operating-system errors.
Verify injected `RuntimeError` and `ArgumentError` evaluation failures propagate unchanged.
For each executable, assert raw output with trailing newlines, non-string JSON, unchanged default output, syntax/type failures, and pretty/raw usage rejection.
Use the timeout and cleanup pattern from `cli_pretty_spec.rb` to verify conflict rejection completes while stdin remains open.

- [ ] **Step 4: Confirm feature failures.**

Run the Step 1 command with `spec/integration/cli_raw_output_spec.rb` added.
Expect failures for the unsupported flag and changed usage, without setup failures.

- [ ] **Step 5: Implement the flag, conflicts, and private types.**

Register `raw-output` alongside the boolean flags, retaining repeat rejection.
Thread its boolean through the positional fast path, parsed tuple, `run`, and `execute` using the interfaces above.
Reject pretty/raw combinations in `check_sources`, before validation handling or input access.
Reject raw output in the allowed query-file validation branch while preserving the two-argument validation fast path.
In `execute`, evaluate once; for a raw string, pass the result plus one newline to `stdout.puts`.
Otherwise retain the selected JSON generator and output behavior.
Keep exception handling and input read order unchanged.
Update usage, help, YARD descriptions, and private RBS signatures; preserve `sig/jmespath.rbs`.

- [ ] **Step 6: Confirm the CLI regressions pass.**

Run the Step 4 command and require zero failures.

- [ ] **Step 7: Document raw output.**

Add `jmespath --raw-output 'user.name' < document.json` to the README command-line examples.
Explain literal string output, JSON fallback, exactly one appended newline, and preserved embedded/trailing newlines in the README and errors guide.
Explain repeats, pretty/validation conflicts, and the exact `--validate --raw-output` exception.
State that raw output preserves stderr diagnostics and failure statuses, with empty stdout before output starts.
Retain default compact and pretty behavior; do not advertise JSON Lines support.

- [ ] **Step 8: Verify and commit the feature.**

Run `bundle exec rake`; require successful lint, RBS, Steep, tests, full coverage, complexity, and documentation checks.
Run `bundle exec rake docs`; require successful generation and documentation coverage.
Run the oss-writing prose checker on changed Markdown files and `git diff --check`; require no findings.
Review the diff against the design, mark completed checkboxes, and stage only this task's files.
Commit as `feat(cli): add raw string output`.
Leave unrelated files unstaged; do not push, open a PR, close the issue, or publish without separate authorization.
