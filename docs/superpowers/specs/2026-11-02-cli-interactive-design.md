# CLI interactive query sessions

Status: approved by the user on 2026-11-02.
Scope: [issue #22](https://github.com/svyatov/jmespath-ruby/issues/22).

## Intent and boundaries

Run successive queries against one JSON document without restarting the CLI or rereading the file.
Support both executable names through `CLI.run(argv, stdin:, stdout:, stderr:)`.
Preserve standard JMESPath semantics and all other CLI modes.
Exclude multiline editing, persistent history, completion, reloads, terminal dependencies, and unrelated refactoring.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| A1: Private session class | Keeps commands, prompts, and recovery together | Adds one internal class | Selected by the user |
| A2: More methods in CLI | Uses the existing execution structure | Gives CLI responsibility for the session loop | Rejected |

The user selected O1: display prompts only when stdin is a terminal.
Readers without terminal detection receive no prompts.
The user approved the detailed behavior below.

## Arguments and startup

Accept `jmespath --interactive --file PATH`, with either option order and the established literal-path rules.
Reject repeated flags, positional expressions, `--query-file`, and combinations with other execution modes or information flags.
Other execution modes include `--validate`, `--pretty`, `--raw-output`, and `--json-lines`.
Reject missing `--file` or its value with status 2 before accessing input or files.
Preserve exact option matching and the literal two-argument `--validate EXPRESSION` behavior.

Load and parse the UTF-8 document once through `CLI.read_document` before reading commands or displaying prompts.
Close the document file before entering the session.
Missing, unreadable, or malformed documents end startup with status 1 through the existing diagnostic formatter.
Invalid JSON diagnostics must not expose document contents.

## Session interface and input

Add private `CLI::InteractiveSession` with an interface accepting the parsed document and injected input, output, and diagnostic streams.
Its run method returns an integer exit status.
CLI retains argument validation and document loading; the session owns iteration, commands, prompts, results, and query recovery.

Read one physical line at a time with `gets`; never read all query input at once.
Interpret query bytes as UTF-8, accepting LF, CRLF, and a final line without a newline.
Remove only the line ending before evaluation, preserving query whitespace and diagnostic positions.
Ignore empty lines and lines containing only spaces or tabs.
Recognize `:help` and `:quit` after removing surrounding spaces and tabs for command matching only.
`:help` writes concise session instructions to stderr, including commands, blank lines, and one query per line.
`:quit` stops immediately without reading subsequent lines.
Other lines beginning with a colon after optional spaces or tabs produce an escaped unknown-command diagnostic and continue.
Malformed UTF-8 produces a query-input diagnostic and continues with the next physical line.

Before each read, write `jmespath> ` without a newline to stderr only when stdin supports `tty?` and returns true.
Flush prompts before waiting for input.
EOF returns status 0, including after recovered query failures.
Retain caller ownership of all injected streams.

## Results and failures

Evaluate each expression against the same parsed document using the existing search behavior.
Serialize each successful result completely with `JSON.generate` before writing it with one final newline to stdout.
Flush each result when the output stream supports `flush`, so a caller can receive a result before supplying another query.
Keep results, including null and false, as compact JSON.
Write no result for a failed query.

Recover from JMESPath query errors and JSON serialization errors around evaluation and serialization only.
Render query failures with `CLI::FailureDiagnostic`, preserving syntax carets, type and arity context, and unknown-function suggestions.
Write diagnostics to stderr, flushing when supported, and accept the next line.
Recovered failures do not change the successful exit status of `:quit` or EOF.
Input, output, prompt, and diagnostic stream failures end the session with status 1 where reporting remains possible.
Do not retry failed writes or catch unrelated application exceptions.

Injected input requires `gets`; `tty?` is optional.
Output and diagnostic streams retain `puts`, with optional `flush`; terminal prompts additionally require diagnostic `print` and `flush`.
Do not require `read`, `tty?`, or terminal dependencies from readers used for piped sessions.

## Verification and documentation

Add focused failing regressions before implementation.
Cover successive queries, one document load, Unicode, whitespace, line endings, commands, EOF, and invalid UTF-8 recovery.
Cover syntax, type, arity, and unknown-function failures followed by successful queries and successful session termination.
Verify exact stream routing, prompt detection, flushing, stream ownership, startup failures, and argument rejection before input access.
Use injected readers to verify incremental reads and termination without consuming later commands.
Exercise both executables with piped input and a standard-library pseudo-terminal for prompt behavior.
Verify stream failures terminate while unrelated exceptions propagate.

Update CLI usage, help, README examples, the errors guide, and affected YARD and RBS declarations.
Keep imported compliance fixtures unchanged and add no dependencies or packaged assets.
Run `bundle exec rake` and `bundle exec rake docs`.
Private helper names, internal method organization, and test layout remain builder decisions.
