# CLI pretty JSON output implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--pretty` to both CLI executables while retaining compact output and exact diagnostic behavior.

**Architecture:** Extend the exact-match argument parser and carry a boolean into execution. Serialize the completed result with Ruby's JSON generator before writing stdout.

**Tech Stack:** Ruby 3.3 or later, JSON, OptionParser, RSpec, RBS, and the locked development bundle.

**Spec:** [Approved pretty output design](../specs/2026-11-02-cli-pretty-output-design.md).

## Global constraints

Preserve standard JMESPath semantics, the public Ruby API, and diagnostic behavior.
Exclude colors, key sorting, configurable indentation, additional dependencies, and unrelated CLI refactoring.
Retain `JSON.generate` for default output, byte for byte.
Preserve imported compliance fixtures and public Ruby signatures.
Neither raw output nor JSON Lines processing is part of this change.

## Review focus

- R1: Validation conflicts must fail before either input file opens or stdin is read.
- R2: `--validate --pretty` must validate literal query text and return its syntax diagnostic.
- R3: Newline-containing strings must remain JSON strings with escaped newlines and one terminating newline.
- R4: Options after expressions must work under `POSIXLY_CORRECT`; `--` must retain its delimiter behavior.
- R5: Unicode and multiline query-file diagnostics must retain exact source coordinates and empty stdout.

## File map

| File | Responsibility |
| --- | --- |
| `lib/jmespath/cli.rb` | Parse the flag, reject conflicts, select serialization, and document usage |
| `sig/internal/cli.rbs` | Match private CLI signatures |
| `spec/integration/cli_pretty_spec.rb` | Cover formatting, sources, parsing, diagnostics, and both executables |
| `spec/integration/cli_spec.rb` | Update the literal usage expectation |
| `spec/integration/cli_file_spec.rb` | Update the literal usage expectation |
| `spec/integration/cli_query_file_spec.rb` | Update the literal usage expectation |
| `README.md` | Explain pretty output and show an invocation |
| `docs/guides/errors.md` | Document unchanged diagnostics and validation conflicts |

### Task 1: Add and verify pretty output

**Interfaces:** Preserve `CLI.run(argv, stdin:, stdout:, stderr:) -> Integer`.
Extend private `CLI.parse_arguments(Array[String]) -> [String?, String?, String?, bool, bool]`.
The last two values are `validate` and `pretty`, respectively; both default to false.
Extend private `CLI.execute(expression, path, stdin, stdout, pretty) -> Integer`, with `pretty: bool` as a positional parameter.
Keep the parser's string-valued hash, using presence of the `pretty` key to represent the flag.
Retain all other helper signatures and both executable entry points.

- [x] **Step 1: Verify the CLI baseline.**

Run `bundle exec rspec spec/integration/cli_spec.rb spec/integration/cli_file_spec.rb spec/integration/cli_query_file_spec.rb`.
Require zero failures before modifying behavior.

- [x] **Step 2: Add failing formatting and argument regressions.**

Create `spec/integration/cli_pretty_spec.rb` using the temporary-directory and UTF-8 StringIO patterns from `cli_query_file_spec.rb`.
Define `run_cli(arguments, input:)` to return `[status, stdout, stderr]` and an independent literal `usage` helper.
Use this exact execution usage line in all four CLI spec files: `Usage: jmespath [--pretty] [--file PATH] (EXPRESSION | --query-file PATH)`.
Keep the second usage line unchanged.

The example `prints exact pretty JSON and preserves compact bytes` uses these literal cases:

```ruby
{
  '{"z":{"a":1}}' => "{\n  \"z\": {\n    \"a\": 1\n  }\n}\n",
  '[1,{"a":true}]' => "[\n  1,\n  {\n    \"a\": true\n  }\n]\n",
  '"café"' => "\"café\"\n",
  '"line\\nnext"' => "\"line\\nnext\"\n",
  '42' => "42\n", '1.5' => "1.5\n",
  'true' => "true\n", 'false' => "false\n", 'null' => "null\n",
  '{}' => "{}\n", '[]' => "[]\n"
}.each do |input, expected|
  expect(run_cli(["--pretty", "@"], input: StringIO.new(input))).to eq([0, expected, ""])
  expect(JSON.parse(expected)).to eq(JSON.parse(input))
  expect(run_cli(["@"], input: StringIO.new(input))).to eq([0, "#{input}\n", ""])
end
```

The locked JSON version was checked during planning: empty objects and arrays serialize as `{}` and `[]`.
Add a literal multi-key object with reversed alphabetical order to assert retained insertion order.
The example `supports each query and document source` asserts the nested-object literal above for positional and file queries with stdin and `--file`.
Exercise `--pretty` before and after expressions, equals paths, and `--pretty -- @` with frozen argument arrays.
Assert the argument arrays remain unchanged and file input leaves an unreadable stdin double unused.
For R4, restore `POSIXLY_CORRECT` in `ensure` after testing `@ --pretty` with its value set to `1`.

The example `rejects unsupported arguments before input access` expects `[2, "", usage]` for each invalid argument array.
Include `--pretty` alone, `--pretty --pretty @`, `--pretty=true @`, `--pre @`, `-p @`, and `--pretty @ extra`.
Include combinations with `--help`, `-h`, and `--version` in either order.
For R1, include both orders of `--pretty --validate --query-file PATH`, with and without `--file PATH`.
Also include `--pretty --validate @` and `--pretty -- @ extra`.
Make `File.open` raise on access and supply an unreadable stdin double in these examples.
For R2, assert `--validate --pretty` returns `[1, "", "Expected a digit at line 1, column 1\n--pretty\n^\n"]` without input access.

- [x] **Step 3: Add failing diagnostic and executable regressions.**

The example `preserves complete failure results` asserts literal `[1, "", diagnostic]` triples for compact and pretty invocations.
Reuse the independent expected diagnostics in `cli_spec.rb` for `items[`, `length(@)`, `length()`, `lenght(@)`, and `[::0]`.
Include malformed JSON with a private marker and expect only `Invalid JSON input\n` on stderr.
For R5, reuse exact source and diagnostic literals from `cli_query_file_spec.rb` for multiline syntax, Unicode type, and multiline arity failures.
Test query files against both document sources and test malformed document files with pretty enabled.
Assert missing query or document files return status 1, empty stdout, and the escaped operating-system error.
Assert injected `RuntimeError` and `ArgumentError` evaluation failures propagate unchanged with pretty enabled.

For each of `jmespath` and `jmespath.rb`, use `Open3.capture3` to assert exact nested pretty output and unchanged compact output.
Also assert exact syntax and type diagnostics, malformed JSON failure, and status 2 with usage on a validation conflict.
Use `Open3.popen3` with the timeout and cleanup pattern from `cli_query_file_spec.rb` for the conflict.
Assert process completion while stdin remains open and stdout remains empty.

- [x] **Step 4: Run the CLI regressions and confirm feature failures.**

Run `bundle exec rspec spec/integration/cli_pretty_spec.rb spec/integration/cli_spec.rb spec/integration/cli_file_spec.rb spec/integration/cli_query_file_spec.rb`.
Expect failures because `--pretty` is unrecognized and usage lacks the flag, not because the test setup fails.

- [x] **Step 5: Implement the flag and update private types.**

In `CLI.argument_parser`, register only `--pretty`, reject repeats, and store presence in the parser hash.
In `CLI.check_sources`, reject pretty validation before returning from the valid query-file validation branch.
Thread the boolean through `parse_arguments`, its positional fast path, `run`, and `execute` using the interfaces above.
Preserve the two-argument validation fast path before parsing.
In `execute`, evaluate once, serialize once with the selected JSON generator, then write with `puts`.
Keep exception handling and document/query read order unchanged.
Add `[--pretty]` to the execution usage line and explain two-space output, compact defaults, repetition, and validation rejection in help.
Update `sig/internal/cli.rbs` and affected YARD descriptions without adding a public Ruby option.

- [x] **Step 6: Run the CLI regressions and confirm zero failures.**

Run the Step 4 command and require zero failures.

- [x] **Step 7: Document the output contract.**

Add a `--pretty 'items'` shell example to the README command-line section.
Describe the compact default, two-space indentation, JSON scalar output, final newline, and supported input sources.
Document repeated-flag rejection and the validation conflict in the README and errors guide.
State that the exact two-argument `--validate --pretty` invocation still validates literal query text.
State that pretty formatting preserves stderr diagnostics, failure statuses, and empty stdout before output starts.
Do not advertise raw output or JSON Lines support.

- [x] **Step 8: Run the required checks.**

Run `bundle exec rake` and require a successful exit, including full coverage and type checks.
Run `bundle exec rake docs` and require a successful exit.
Run the repository prose checker on changed Markdown files and `git diff --check`; require no findings.
Review the final diff against the approved design and keep unrelated files unstaged.

- [x] **Step 9: Commit the complete feature.**

Stage only the files in the file map and this plan's completed checkboxes.
Use `feat(cli): add pretty JSON output` as the commit subject.
Do not push, open a PR, close the issue, or publish without separate authorization.

## Verification results

The baseline CLI suite passed 179 examples.
The extended suite failed before implementation because `--pretty` was unrecognized and usage lacked the flag.
The full `bundle exec rake` check passed 6,372 examples with 100% line and branch coverage.
Lint, RBS validation, Steep, coverage-aware complexity, and documentation checks passed.
`bundle exec rake docs` passed with 100% documented public interfaces.
Independent QA passed 200 subprocess checks across both executable names.
