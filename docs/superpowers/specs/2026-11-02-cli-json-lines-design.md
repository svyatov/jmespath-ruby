# CLI JSON Lines input

Status: approved by the user on 2026-11-02.
Scope: [issue #21](https://github.com/svyatov/jmespath-ruby/issues/21).

## Intent and boundaries

Process independent JSON records through both CLI executables without loading the complete input.
Add `--json-lines` for stdin and `--file PATH`, with positional queries and `--query-file PATH`.
Preserve default document processing, standard JMESPath semantics, and readable query diagnostics.
Exclude parallel evaluation, multiline records, automatic format detection, recovery after failures, dependencies, and unrelated CLI refactoring.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| O1: Add a private JSON Lines execution path | Reuses CLI parsing, compiled expressions, and diagnostics | Adds an execution path to the CLI module | Selected by the user |
| O2: Extract a private record processor | Separates iteration and record context | Adds an abstraction for one CLI mode | Rejected for this scope |

The user selected query compilation before reading any records.
The user approved the argument, record-processing, diagnostic, and verification contracts below.

## Arguments and query preparation

Recognize the full `--json-lines` flag before or after the positional query, without a short alias or value.
Reject repetitions and combinations with `--pretty`, `--raw-output`, or syntax validation with usage status 2.
Reject usage failures before opening query or document files or consuming stdin.
Preserve exact option matching, delimiter handling, standalone information requests, literal paths, and caller ownership of arguments.
Preserve the exact two-argument form `--validate EXPRESSION`, including literal flag-like expressions such as `--json-lines`.

Read the selected query source, then call `JMESPath.compile` once before opening the document file or reading stdin.
A valid query with empty input succeeds without output.
An invalid query fails with status 1 even when input is empty.
Compilation failures have query diagnostics without an input line number because record processing has not started.
Preserve input-before-query error precedence in default document mode.

## Record processing

Read one physical line at a time using the stream's `gets` method with its default newline separator.
Parse each line as a complete JSON value, including scalars, arrays, objects, null, and false.
Accept LF and CRLF endings and a final record without a newline.
Reject blank and whitespace-only lines as invalid JSON records.
Evaluate each parsed value with the compiled expression.
Serialize the complete result with `JSON.generate` before writing it with one final newline.
Write null and false results as `null` and `false`.

Read the next record only after writing the preceding result.
Stop at the first parsing, evaluation, input, or output failure handled by the CLI.
Do not read subsequent records or write a result for a record whose parsing or evaluation fails.
Retain previously written results; callers must inspect the exit status before treating output as complete.
Keep memory proportional to the current record, its evaluation, and its serialized result, plus the compiled query.
Use normal output buffering without adding a flush protocol.

Close files opened by the CLI after success or failure.
Leave caller-owned stdin and output streams open.
Retain support for read-only injected streams in document mode.
Document the additional `gets` requirement for injected streams in JSON Lines mode and represent it in RBS.
Keep the output protocol limited to `puts`.

## Diagnostics

Prefix record failures with a separate `Input line N:` line, using a one-based physical input line number.
Render the underlying error through `CLI::FailureDiagnostic` after the prefix.
Preserve query excerpts, query line and column numbers, carets, and function validation context.
Malformed and blank records retain the generic `Invalid JSON input` message without document contents.
Record failures return status 1; usage failures return status 2.
File-open and query-preparation failures use ordinary diagnostics without a record number.
Do not catch unrelated application exceptions.

## Verification and documentation

Add focused regression tests before implementation.
Cover multiple records, all JSON result types, empty input, CRLF, Unicode, and the final unterminated line.
Cover blank lines, whitespace-only lines, malformed later records, and later evaluation failures.
Verify exact diagnostics, retained output, absent failed-record output, and termination at the failing record.
Use an instrumented reader to reject whole-stream reads and verify ordering between reads and writes.
Verify one compilation, invalid-query rejection before input access, file closure, and caller stream ownership.
Cover option conflicts, query sources, argument preservation, and both executable names.
Preserve default document behavior and imported compliance fixtures.

Update CLI help, the README, and the errors guide with examples, conflicts, partial output, and memory behavior.
Update affected RBS declarations and YARD descriptions, including stream requirements.
Run `bundle exec rake` and `bundle exec rake docs`.
Coordinate the `--raw-output` conflict with its approved design without implementing that separate feature here.
Private helper signatures and test organization remain builder decisions.
