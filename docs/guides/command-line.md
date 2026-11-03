# Command-line reference

## Quick start


Both `jmespath` and `jmespath.rb` accept an expression and a JSON document from stdin or `--file PATH`.
Use `--query-file PATH` to read the expression from a UTF-8 file.
See [shell completion](completion.md) for manual Bash and Zsh setup for both executable names.

```sh
printf '%s\n' '{"user":{"name":"Ada"}}' | jmespath 'user.name'
jmespath --file document.json 'user.name'
jmespath 'user.name' --file document.json
jmespath --file 'my document.json' 'user.name'
jmespath --file=--document.json 'user.name'
jmespath --file ./--document.json 'user.name'
jmespath --file - 'user.name'
jmespath --file document.json -- 'user.name'
jmespath --query-file query.jmespath < document.json
jmespath --query-file query.jmespath --file document.json
jmespath --pretty 'items' < document.json
jmespath --raw-output 'user.name' < document.json
```

## Input

Document files are read as UTF-8 and closed after parsing, before query evaluation in single-document mode.
File input leaves stdin unused; omitting `--file` selects stdin.
Paths are literal: `--file -` reads a file named `-`.
Quote filenames with spaces; use the equals form or `./` prefix for option-like filenames.
Options can precede or follow the expression; `--` ends option parsing.
Supply exactly one query source: a positional expression or `--query-file PATH`.
Repeated file options, unknown options, missing values, and conflicting or absent query sources are usage failures.
Version flags must appear alone; help accepts one optional topic, as described under [Help](#help).

Query files retain all source text, including trailing newlines and Unicode diagnostic coordinates.
An empty query file produces a syntax failure.
Query files close after reading, before document input is accessed.
Missing or unreadable query files leave document input untouched.
In single-document mode, execution parses JSON before compiling the expression.
Query paths follow the document path rules: `--query-file -` reads a literal file named `-`.

## Output

The result goes to standard output as compact JSON followed by a newline.
Use `--pretty` for JSON with two-space indentation and one final newline.
Both formats support objects, arrays, strings, numbers, booleans, and null, with Unicode preserved.
Pretty output works with positional or file queries and either document source.
Repeated `--pretty` options are usage failures.
Pretty formatting preserves stderr diagnostics, source coordinates, and exit statuses; failures before output starts leave stdout empty.
Use `--raw-output` to print string results without JSON quotes or escape encoding.
Other result types retain compact JSON encoding.
Raw output appends one newline and preserves every embedded and trailing newline in the result.
An empty string produces one newline; a string ending with one newline produces two.
Repeated `--raw-output` options and combinations with `--pretty` are usage failures.
Raw output preserves stderr diagnostics, source coordinates, and exit statuses; failures before output starts leave stdout empty.
Syntax, function type, and arity failures include source coordinates, a query excerpt, and a caret when available.
Unknown functions suggest similar registered names.
Malformed JSON input reports `Invalid JSON input` without including document fragments.
These failures go to standard error and exit with status 1.
Usage failures exit with status 2; `--help` and `--version` exit with status 0 without reading input.

### Record processing

Process independent JSON records with these shell commands:

```sh
jmespath --json-lines 'user.name' < events.jsonl
jmespath --json-lines --file events.jsonl --query-file query.jmespath
```

JSON Lines mode compiles the query once before opening document input or reading stdin.
Each physical line must contain one complete JSON value; blank and whitespace-only lines fail.
LF, CRLF, and a final record without a newline are accepted.
Each result is compact JSON followed by a newline, including `null` and `false`.
Empty input succeeds without output when the query is valid; an invalid query still fails.

Processing stops at the first failure with status 1 and an `Input line N:` diagnostic prefix.
Earlier results remain on stdout; check the exit status before treating output as complete.
Query compilation and file-open errors have no input line prefix.
Memory is proportional to the current record, its evaluation, and its serialized result, plus the compiled query.
Output uses normal buffering.
Owned files close after processing; caller-owned streams remain open.
Injected `CLI.run` input needs `gets` for JSON Lines or `read` for document mode; output needs only `puts`.
Repeated `--json-lines` flags and combinations with `--pretty`, `--raw-output`, or validation are usage failures.

## Validation

Validate syntax without providing a JSON document by running this shell command:

```sh
jmespath --validate 'items[*].name'
jmespath --validate --query-file query.jmespath
jmespath --query-file query.jmespath --validate
```

Both executables support `--validate EXPRESSION` without reading standard input.
File validation also leaves stdin untouched and rejects document options such as `--file`.
Combining `--pretty` with validation is a usage failure, rejected before opening input files or reading stdin.
Combining `--raw-output` with validation follows the same rule.
The exact two-argument form `--validate EXPRESSION` always treats the second argument as query text, including flag-like text.
Thus `jmespath --validate --pretty` validates the literal expression `--pretty`.
Likewise, `jmespath --validate --raw-output` validates the literal expression `--raw-output`.
Valid syntax produces no output and exits with status 0.
Query failures print a diagnostic to standard error and exit with status 1; incorrect usage exits with status 2.
Validation does not check function availability or runtime argument types.
The Ruby interface is `JMESPath.validate(expression, max_depth: 128)`.
See [CLI diagnostics](errors.md#cli-diagnostics) for examples and fallback behavior.

## Functions

List built-in functions from the shell without reading stdin:

```sh
jmespath --functions
```

Each line shows a name, accepted argument types, and the description from public function metadata.
The listing is alphabetical and ends with a notation legend.
Unions use `|`, homogeneous arrays use `array<T>`, and expression references use `expref`.
A final `...` means the last argument repeats and remains required.
Runtime checks can be narrower than the declared types.
See [the function listing](functions.md#command-line-reference) for examples.

Use `--functions` alone; queries, paths, other modes, repeated flags, and values are usage failures.
The two-argument form `--validate --functions` retains literal query validation.
Listing exits with status 0 on success, 1 for output failures, or 2 for usage failures.
Usage failures leave stdout empty and print usage guidance on stderr.

## Interactive

Start a session against one loaded document:

```sh
jmespath --interactive --file document.json
```

Enter one UTF-8 query per line; empty lines and lines containing only spaces or tabs are ignored.
Use `:help` for session instructions and `:quit` to finish, or end input with EOF.
Queries accept LF, CRLF, and a final line without a newline.
Each successful query prints compact JSON and a final newline to stdout, then flushes when the stream supports it.
Prompts appear only when stdin is a terminal; prompts, help, and diagnostics use stderr.
The document loads once and its file closes before the first prompt or command read.

Queries can also come from a pipe without prompts:

```sh
printf 'user.name\nlength(user.name)\n' | jmespath --interactive --file document.json
```

Query errors, unknown commands, and invalid UTF-8 query lines produce diagnostics and allow the session to continue.
Failed queries produce no JSON result; successful results remain available.
EOF and `:quit` return status 0 even after query failures.
Document and stream failures terminate with status 1; usage failures return status 2.
Interactive mode requires `--file PATH` and rejects positional queries, `--query-file`, other modes, information flags, and repeated flags.
Readers supplied to `CLI.run` need `gets`; `tty?` is optional and absent detection means no prompts.
Writers need `puts`; `flush` is optional except for terminal prompts, whose diagnostic stream needs both `print` and `flush`.
Caller-owned streams remain open; history, completion, multiline editing, and document reloads are unavailable.

## Help

Run `jmespath --help` or `jmespath -h` for usage, options, common examples, and topic commands.
Read detailed rules without accessing stdin or opening document or query files:

```sh
jmespath --help input
jmespath --help output
jmespath --help validate
jmespath --help functions
jmespath --help interactive
```

Both executable names accept `-h TOPIC` as an alias.
Help must be the first argument, with zero or one exact, case-sensitive topic name.
Abbreviations, equals forms, unknown topics, extra arguments, and combinations with execution flags are usage failures.
Invalid help requests leave stdout empty and print usage guidance to stderr without accessing any input.
Valid help writes to stdout with status 0; output failures return 1 and usage failures return 2.
The exact two-argument form `jmespath --validate --help` still validates the literal query `--help`.

Run `jmespath --version` for the gem version.
The version flag must appear alone and leaves document and query input untouched.

## Exit statuses

| Status | Meaning |
| --- | --- |
| 0 | Successful execution, validation, information output, or normal session termination |
| 1 | Query, document, file, or stream failure |
| 2 | Invalid command-line usage |

Usage failures leave stdout empty and write usage guidance to stderr before accessing input.
Function arguments and expression-reference results are validated; failures exit with status 1.
See [CLI diagnostics](errors.md#cli-diagnostics) for source locations and fallback messages.
