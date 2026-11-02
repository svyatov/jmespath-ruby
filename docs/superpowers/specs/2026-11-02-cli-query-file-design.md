# CLI query files

Status: approved by the user on 2026-11-02.
Scope: [issue #18](https://github.com/svyatov/jmespath-ruby/issues/18).

## Intent and boundaries

Let users execute or validate saved UTF-8 queries without shell quoting or copying their contents into arguments.
This is a small change shared by `jmespath` and `jmespath.rb`.
Preserve positional queries, compact JSON output, standard JMESPath semantics, and the public Ruby API.
Exclude includes, templates, substitution, multiple queries, additional dependencies, and unrelated CLI refactoring.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| O1: Extend the parser and validation handler | Shares file reading and diagnostics while preserving positional validation | Keeps separate validation argument rules | Selected by the user |
| O2: Unify execution and validation parsing | Centralizes argument rules | Broadens the refactor and compatibility checks | Not selected |

The user also selected query-file support for syntax validation.
Validation remains syntax-only and leaves document input untouched.

## Argument contract

Support these invocations:

```sh
jmespath --query-file query.jmespath < document.json
jmespath --query-file query.jmespath --file document.json
jmespath --file document.json --query-file query.jmespath
jmespath --validate --query-file query.jmespath
jmespath --query-file query.jmespath --validate
```

Require exactly one query source: one positional expression or one query file.
An empty file supplies an empty expression and produces a query failure.
Reject absent or conflicting query sources, repeated file options, unknown options, and missing option values with status 2.
Reject usage failures before opening files or reading stdin.
Preserve standalone help and version behavior and reject combinations with other arguments.
Preserve caller ownership of `argv` and stdin.

The proposed path rules match `--file`: accept separated and equals values, quoted spaces, and literal paths.
For option-like filenames, document the equals form or a relative path.
The path `-` names a literal file; it does not select stdin.
The delimiter `--` ends option parsing.

Preserve the exact two-argument form `--validate EXPRESSION`, including expressions that resemble flags.
Consequently, `--validate --query-file` validates the literal expression `--query-file`.
The execution form `--query-file` without a value is a usage failure.
Reject document options in validation mode.
The path rules, option ordering, and legacy validation precedence above are implementation proposals for approval.

## Reading and evaluation

Read query files as UTF-8 without trimming, newline conversion, or source rewriting.
Close owned query files after reading, including read failures.
Read the query file before accessing the document, so missing or unreadable queries leave document input untouched.
After reading the query source, preserve execution's document-before-query-compilation order.
Thus malformed JSON retains precedence over syntax failures when both inputs are readable.
Validate file queries without opening a document or reading stdin.
Use the lexer's invalid-encoding diagnostic for malformed UTF-8 query text.

## Diagnostics

Reuse the diagnostic renderer introduced by issue #23.
Preserve source excerpts, line numbers, character columns, carets, and structured function type and arity details.
Pass the original query text to runtime diagnostics.
Report query-file open and read failures on stderr with status 1 and escaped operating-system messages.
Keep stdout empty on expected failures and retain status 2 for usage failures.
Do not add filename prefixes or change public diagnostic formats.
Do not catch unrelated application exceptions.

## Verification and documentation

Add focused failing regression tests before implementation.
Cover multiline queries, Unicode, trailing newlines, empty files, invalid encoding, and exact syntax and function diagnostics.
Cover absent and conflicting sources, repeated options, missing values, path forms, delimiters, and argument preservation.
Verify missing and unreadable query files leave stdin and document files untouched.
Verify owned-file closure on success and failure.
Exercise execution with stdin and `--file`, syntax validation, and both executables.
Retain positional validation behavior, including flag-like query text.
Update CLI help, the README, the errors guide, and private RBS declarations as needed.
Preserve imported compliance fixtures and public Ruby signatures.
Run `bundle exec rake` and `bundle exec rake docs`.

Private helper names and test organization remain builder decisions.
