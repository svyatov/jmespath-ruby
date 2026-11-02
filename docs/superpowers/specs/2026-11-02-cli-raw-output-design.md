# CLI raw string output

Status: approved by the user on 2026-11-02.
Scope: [issue #20](https://github.com/svyatov/jmespath-ruby/issues/20).

## Intent and boundaries

Let shell consumers use string results without decoding JSON through `--raw-output`.
This is a small change shared by `jmespath` and `jmespath.rb`.
Preserve default output, standard JMESPath semantics, public Ruby interfaces, and readable diagnostics.
Exclude array joining, NUL delimiters, newline suppression, implicit string conversion, dependencies, and unrelated CLI refactoring.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| O1: Add a flag to the execution path | Reuses parsing, execution, and diagnostics | Adds one private flag | Selected by the user |
| O2: Replace formatting flags with an output-mode value | Makes mode selection explicit | Requires a broader refactor | Rejected for this scope |

## Argument contract

Accept `--raw-output` before or after a positional query and alongside `--file` and `--query-file`.
Recognize the full flag only, with no short alias or value.
Reject repeated flags and combinations with `--pretty` or syntax validation with usage status 2.
Reject conflicts before opening either input file or reading stdin.
Preserve exact option matching, delimiter handling, standalone help and version behavior, and caller ownership of `argv`.

The user confirmed preservation of the exact two-argument form `--validate EXPRESSION`.
Thus `jmespath --validate --raw-output` validates the literal query `--raw-output`.
An actual combination, such as `--raw-output --validate --query-file query.jmespath`, is a usage failure.

JSON Lines processing remains outside this change.
Issue #21 must add the conflict with `--raw-output` when introducing `--json-lines`.

## Output and diagnostics

Evaluate the complete query before writing output.
For string results with `--raw-output`, write the string unchanged and append exactly one newline.
Preserve Unicode, quotes, backslashes, embedded newlines, and every trailing newline in the string.
An empty string produces one newline; a string ending with one newline produces two.
Pass the string plus one newline to `puts` to preserve the public output protocol, which requires only `puts`.
Calling `puts` with the result alone would omit the additional newline when the result ends with one.

For non-string results, retain compact JSON encoding followed by one newline.
Preserve compact and pretty output byte for byte when raw output is absent.
Reuse the diagnostic renderer without converting failures into result strings.
Keep stdout empty on usage, input, syntax, and evaluation failures before output starts.
Preserve stderr text, source context, and exit statuses; propagate unrelated application exceptions.

## Verification and documentation

Add focused failing regression tests before implementation.
Check exact output for empty strings, Unicode, quotes, backslashes, embedded newlines, and trailing newlines.
Check arrays, objects, numbers, booleans, and null retain JSON encoding.
Cover flag order, file sources, repeated flags, unsupported values, conflicts, and unchanged `argv`.
Verify conflict rejection leaves stdin unread and input files unopened.
Verify default output and pretty output remain unchanged.
Compare diagnostics with and without raw output for malformed JSON, syntax, type, arity, unknown-function, and invalid-value failures.
Include multiline and Unicode query-file diagnostics and verify both executable names.

Update CLI help, the README, and the errors guide with raw output and conflict rules.
Update affected private RBS declarations and YARD descriptions.
Preserve imported compliance fixtures and public Ruby signatures.
Run `bundle exec rake` and `bundle exec rake docs`.

Private helper signatures and test organization remain builder decisions.
