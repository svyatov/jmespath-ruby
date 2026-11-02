# CLI interactive query sessions implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Evaluate successive stdin queries against one loaded JSON file through both CLI executables.

**Architecture:** Keep argument validation and document loading in `JMESPath::CLI`. Add private `CLI::InteractiveSession` to own commands, prompts, output, and recovery. Reuse search semantics and `CLI::FailureDiagnostic`.

**Tech stack:** Ruby 3.3+, standard-library JSON, OptionParser, PTY, RSpec, RBS, Steep, and the locked bundle.

**Spec:** [Approved interactive design](../specs/2026-11-02-cli-interactive-design.md).

## Global constraints

- Preserve standard JMESPath semantics and all other CLI modes.
- Exclude multiline editing, persistent history, completion, reloads, terminal dependencies, and unrelated refactoring.
- Load and parse the UTF-8 document once through `CLI.read_document` before reading commands or displaying prompts.
- Retain caller ownership of all injected streams.
- Keep imported compliance fixtures unchanged and add no dependencies or packaged assets.
- Add focused failing regressions before implementation.
- Run `bundle exec rake` and `bundle exec rake docs`.

## Review focus

- R1: A pipe remains open after one query; its result must arrive before the next query is sent.
- R2: Terminal input with redirected stderr still produces prompts because stdin determines terminal detection.
- R3: A diagnostic write failure must terminate without recursively attempting to report its own failure.
- R4: Whitespace in expressions must retain caret coordinates even though command matching ignores surrounding spaces and tabs.
- R5: Usage errors must not touch files or stdin; literal `--validate --interactive` remains query validation.

## File map

| File | Responsibility |
| --- | --- |
| `lib/jmespath/cli/interactive_session.rb` | Private session loop, commands, prompts, query recovery, and stream failures |
| `lib/jmespath/cli.rb` | Require, dispatch, usage, help, and stream documentation |
| `lib/jmespath/cli/arguments.rb` | Interactive flag, argument tuple, and exclusive mode validation |
| `sig/internal/cli.rbs` | Private session declarations and argument tuple |
| `sig/jmespath.rbs` | Document mode-specific stream protocols without restricting other modes |
| `spec/unit/cli_interactive_session_spec.rb` | Session behavior through injected streams |
| `spec/integration/cli_interactive_spec.rb` | Startup, argument validation, file lifetime, pipes, and terminal behavior |
| `spec/integration/cli*_spec.rb` | Literal usage expectations affected by the additional usage line |
| `README.md`, `docs/guides/errors.md` | Interactive examples, stream protocols, recovery, conflicts, and exit statuses |

### Task 1: Implement the private session

**Interfaces:** Add `CLI::InteractiveSession.new(data, input:, output:, errors:)` and `#run -> Integer`.
`data` is a `JMESPath::value`; input implements `_LineReader#gets -> String?`; output and errors implement `_Writer#puts`.
Detect `tty?` through capability checks; readers without it are nonterminal readers.
Use optional `flush` on output and diagnostics; terminal diagnostics additionally require `print` and `flush`.
Represent optional capabilities through narrow internal RBS interfaces and runtime checks, preserving the public writer protocol.

- [x] **Step 1: Establish the session tests.**

Create a helper returning `[status, output.string, errors.string]` from a real session with StringIO streams.
Use data `{"name" => "café", "flag" => false}` and these assertions:

```ruby
expect(session("name\nmissing\nflag\n")).to eq([0, "\"café\"\nnull\nfalse\n", ""])
expect(session("\n \t\r\nname\r\nflag")).to eq([0, "\"café\"\nfalse\n", ""])
expect(session("  :quit\t\nname\n")).to eq([0, "", ""])
```

Assert `:help` writes only stderr and permits a following valid query.
Assert an unknown colon command containing an escape byte produces an escaped diagnostic and permits a following query.
Assert invalid UTF-8 bytes on one line produce a diagnostic, followed by a valid result from the next line.
Use a gets-only reader without `tty?` to prove no whole-stream read or terminal methods are required.
Observe incremental reads, retained stream ownership, and no reads after `:quit`.

- [x] **Step 2: Add diagnostic and stream regressions.**

Evaluate `items[`, `length(flag)`, `length()`, and `lenght(name)` followed by `name`, ending separately with EOF and `:quit`.
Assert status 0, one successful result, no failed-query result, exact syntax/type/arity caret diagnostics, and the `length` suggestion.
For R4, use `  length()` and a Unicode expression before a failing function call; assert the unchanged excerpt and correct caret position.
Induce `JSON::GeneratorError` during result serialization; assert its generic diagnostic and subsequent success.
Assert unrelated RuntimeError and ArgumentError propagate from evaluation.

For R1, verify a result write and optional flush happen before the next input read.
For R2, use terminal input with separate diagnostic and result streams; assert `jmespath> ` goes only to stderr before each read.
Assert prompt flushing precedes input reads, including the read that discovers EOF.
Cover `tty?` returning false and being absent, and writers with and without optional `flush`.
Induce IOError and SystemCallError in reads, writes, and flushes; assert status 1 and no further reads.
For R3, fail diagnostic writes and prompt writes; assert status 1 without reporting loops or repeated failed writes.
Retain successful results preceding any terminal stream failure.

- [x] **Step 3: Confirm the tests fail for the missing session.**

Run `bundle exec rspec spec/unit/cli_interactive_session_spec.rb`.
Expect failures caused by the absent session class, rather than invalid test setup.

- [x] **Step 4: Implement the private session and its RBS declarations.**

Create `lib/jmespath/cli/interactive_session.rb` with `@api private` and the Task 1 interface.
Normalize line endings without stripping expression whitespace; use a separate command comparison string.
Treat only spaces and tabs as ignorable blank-line content after removing LF or CRLF.
Validate UTF-8 before command parsing or evaluation.
Keep query-error recovery around search and complete serialization, outside result writes and flushes.
Use `CLI::FailureDiagnostic.format(error, expression)` for query and serialization failures.
Use ordinary escaped diagnostics for unknown commands and invalid UTF-8, without including malformed bytes directly.
Handle stream failures once at session scope; if failure reporting also fails, return 1 without another reporting attempt.
Leave unrelated exceptions visible.
Declare the class and capability interfaces in `sig/internal/cli.rbs`.

- [x] **Step 5: Verify the session.**

Run `bundle exec rspec spec/unit/cli_interactive_session_spec.rb`; require zero failures.

- [x] **Step 6: Commit the private session and focused tests.**

Combine this commit with Task 2 so the private session is connected to the CLI.
The atomic-commits requirement excludes unconnected private code.

### Task 2: Expose and verify interactive CLI mode

**Interfaces:** Preserve `CLI.run(argv, stdin:, stdout:, stderr:) -> Integer`.
Append `interactive: bool` to `parse_arguments(Array[String]) -> [String?, String?, String?, bool, bool, bool, bool, bool]`.
Require exactly one file path and no query source when interactive is true.
Dispatch to `InteractiveSession.new(read_document(path, stdin), input: stdin, output: stdout, errors: stderr).run` before reading a query source.
Task 1 owns session behavior; this task owns startup and compatibility.

- [x] **Step 1: Verify the CLI baseline.**

Run `bundle exec rspec spec/integration/cli_spec.rb spec/integration/cli_file_spec.rb spec/integration/cli_query_file_spec.rb spec/integration/cli_pretty_spec.rb spec/integration/cli_raw_output_spec.rb spec/integration/cli_json_lines_spec.rb spec/integration/cli_functions_spec.rb`.
Require zero failures before editing CLI dispatch.

- [x] **Step 2: Add failing argument and startup regressions.**

Create `spec/integration/cli_interactive_spec.rb` using temporary UTF-8 files and injected streams.
For a file containing `{"name":"café"}`, assert `--interactive --file PATH` and the reverse order return `[0, "\"café\"\n", ""]` for `name\n:quit\n`.
Assert the file opens once and closes before the first command read; mutate its contents between reads and retain the original document.
Cover scalar, null, and false documents as valid startup values.
Cover spaces, option-like filenames, `--file=PATH`, literal `-`, delimiter handling, frozen argv, and `POSIXLY_CORRECT`.

For R5, reject missing files options, missing option values, duplicate flags, positional queries, and query-file combinations without file or stdin access.
Reject interactive combinations with validate, pretty, raw-output, json-lines, functions, help, and version, in both orders where relevant.
Preserve standalone information flags and exact two-argument `--validate --interactive` as syntax validation, independent of stdin.
Reject abbreviated interactive flags through the existing exact-match parser.
Assert a nonexistent path, directory, permission failure, read failure, and malformed JSON end startup with status 1 before prompts or command reads.
Assert malformed JSON retains `Invalid JSON input` without private document contents.
Update literal usage expectations with a separate `jmespath --interactive --file PATH` line.

- [x] **Step 3: Confirm feature failures.**

Run `bundle exec rspec spec/integration/cli_interactive_spec.rb`.
Expect unsupported-flag failures from the missing interactive dispatch.

- [x] **Step 4: Implement argument validation, dispatch, help, and stream types.**

Register exact `--interactive` with the existing repetition checks in `arguments.rb`.
Extend both tuple construction paths; check exclusive modes and interactive sources before opening files.
Keep `literal_validation?` before general argument parsing.
Require the session class in `cli.rb`, extend usage, and dispatch through the Task 2 interface.
Keep read-only document inputs and gets-only JSON Lines inputs supported.
Update private signatures, public protocol comments, and CLI YARD for interactive input and optional terminal capabilities.

- [x] **Step 5: Verify both executable entry points and terminal behavior.**

For each of `exe/jmespath` and `exe/jmespath.rb`, use Open3 for successive valid queries, recovered failures, `:help`, `:quit`, EOF, and startup failures.
Assert JSON-only stdout, diagnostic-only stderr, no piped prompts, and exact exit statuses.
For R1, keep the Open3 stdin pipe open after writing one query; use a bounded timeout to receive its result before sending `:quit`.
Use standard-library `PTY.open` for stdin only, with separate stdout and stderr pipes, to cover R2 through both executables.
Wait for the exact prompt before sending a query, then receive its result before sending `:quit`.
Use bounded timeouts, close all descriptors, and terminate and reap child processes in failure cleanup.
Run the complete CLI spec set and Task 1 tests; require zero failures.

- [x] **Step 6: Document and verify the public behavior.**

Update README and the errors guide with terminal and piped examples, exclusive flags, commands, stream requirements, recovery, and statuses.
Explain that earlier query failures still permit status 0 on `:quit` or EOF; stream and startup failures return 1, usage failures return 2.
State that only terminal stdin receives prompts, all prompts and diagnostics use stderr, and each result is compact JSON on stdout.
Run `env RUBOCOP_CACHE_ROOT=/private/tmp/jmespath-rubocop-cache bundle exec rake` and `bundle exec rake docs`.
Require zero failures, 100% line and branch coverage, and passing RBS, Steep, CRAP, and documentation checks.
Run `git diff --check` and review the diff for preserved fixtures and unrelated changes.

- [x] **Step 7: Commit the CLI feature and documentation.**

Stage only the files in the approved scope.
Use `feat(cli): expose interactive query mode`.
Do not push, merge, or publish without separate authorization.

## Completion evidence

The final `bundle exec rake` run passed 6,686 examples with 100% line and branch coverage.
RuboCop, RBS, Steep, CRAP analysis, and documentation checks passed.
`bundle exec rake docs`, prose checks, and whitespace checks passed.
Independent review identified two issues, each reproduced by a failing regression before its fix.
Regressions cover JSON nesting during result serialization and a failed startup diagnostic write.
Help constants and query dispatch were extracted to meet the repository's size limits.
