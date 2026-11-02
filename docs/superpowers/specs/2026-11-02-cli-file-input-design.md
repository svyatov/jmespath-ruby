# Explicit JSON file input

Status: approved by the user on 2026-11-02.
Scope: [issue #17](https://github.com/svyatov/jmespath-ruby/issues/17).

## Intent and scope

Let CLI users select one JSON document with `--file PATH` without shell redirection.
Keep stdin as the default input and retain one positional query.
This is a small change shared by `jmespath` and `jmespath.rb`.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| O1: Standard-library `OptionParser` | Shares option parsing and usage failures across CLI flags | Requires explicit compatibility rules for positional queries | Selected by the user |
| O2: Custom argument parser | Controls each accepted argument form directly | Requires custom handling for missing values, unknown options, and delimiters | Not selected |

The user selected literal path handling: `--file -` reads a file named `-`.
Omitting `--file` selects stdin.
No gem dependencies are added.

## Argument contract

Accept these shell invocations:

```sh
jmespath 'user.name' < document.json
jmespath --file document.json 'user.name'
jmespath 'user.name' --file document.json
jmespath --file 'my document.json' 'user.name'
jmespath --file=--document.json 'user.name'
jmespath --file ./--document.json 'user.name'
jmespath --file - 'user.name'
jmespath --file document.json -- 'user.name'
```

Options may precede or follow the query, using separated or equals forms.
Use shell quoting for spaces and the equals form or a relative path for option-like filenames.
The `--` delimiter ends option parsing; exactly one expression must remain.
An empty expression remains an expression and follows normal query error handling.
Parse a copy of `argv` without modifying the caller's array.

Reject unknown options, missing option values, repeated `--file`, and missing or extra positional expressions with status 2.
Reject usage failures before reading stdin or opening files.
Preserve standalone `--help`, `-h`, and `--version` with status 0 and no input access.
Reject combinations of informational flags with query arguments or file options as usage failures.
Add no short alias for `--file`.

The user approved these argument rules with this design.

## Input ownership and evaluation

With `--file`, open the selected path as UTF-8 and parse one JSON document.
Use block-based file ownership to guarantee closure after successful parsing and expected or unexpected failures.
Complete file reading and JSON parsing before evaluating the query.
Never read or close the supplied stdin when a file is selected, including when stdin is already closed.
Without `--file`, preserve stdin reading and leave stream ownership with the caller.
Keep compact JSON output and the document-before-query evaluation order.

## Diagnostics and compatibility

Reuse `CLI::FailureDiagnostic` from issue #23 for expected input and query failures.
Pass the parsed expression to the renderer, independently of its position in `argv`.
Report file open and read failures on stderr with status 1.
Report malformed JSON as `Invalid JSON input`, without document fragments.
Retain syntax carets, Unicode columns, function type and arity details, and unknown-function suggestions.
Failures before output starts leave stdout empty.
Escape operating-system error messages through the diagnostic renderer.
Do not catch unrelated application exceptions.
Keep the Ruby search API, standard JMESPath semantics, and imported compliance fixtures unchanged.

## Verification and documentation

Write focused failing regression tests before implementation.
Cover successful files, Unicode, spaces, option-like names, literal `-`, option placement, delimiters, and malformed arguments.
Verify file input never consumes stdin, including a closed or unreadable supplied stream.
Cover missing files, permission failures, malformed JSON, and failures while reading an opened file.
Simulate permission failures where the runtime cannot enforce them reliably.
Verify owned-file closure after success, parse failures, read failures, and query diagnostics.
Cover syntax carets, function type and arity failures, and exact stderr with empty stdout.
Exercise both executables with file success, file failures, query failures, and usage failures.
Retain regression coverage for stdin input, closed stdin, help, version, and compact output.

Update CLI help, the README command-line section, and the errors guide with file input examples.
Update YARD comments and private RBS declarations as needed; preserve the public Ruby method signature.
Run `bundle exec rake` and `bundle exec rake docs`.

## Boundaries and builder decisions

Exclude multiple input files, directory traversal, positional filename inference, and additional input or output modes.
File failures must not silently fall back to stdin.
Private helper names, parser organization, usage wording, and test organization remain builder decisions.
