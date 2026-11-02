# CLI pretty JSON output

Status: awaiting design approval.
Scope: [issue #19](https://github.com/svyatov/jmespath-ruby/issues/19).

## Intent and boundaries

Let CLI users inspect nested results with `--pretty` while preserving compact JSON as the default.
This is a small change shared by `jmespath` and `jmespath.rb`.
Preserve standard JMESPath semantics, the public Ruby API, and diagnostic behavior.
Exclude colors, key sorting, configurable indentation, additional dependencies, and unrelated CLI refactoring.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| A1: Extend argument parsing and select the JSON generator during execution | Reuses the execution path and Ruby's JSON dependency | Extends private argument handling | Selected by the user |
| A2: Introduce a separate output formatter | Provides a place for several output modes | Adds an abstraction for one flag | Rejected as unnecessary for this scope |

The user selected rejection of pretty formatting during syntax validation.
The formatting defaults and argument details below are implementation proposals for approval.

## Argument contract

Accept `--pretty` before or after a positional expression and alongside `--file` and `--query-file`.
Use these forms:

```sh
jmespath --pretty 'items' < document.json
jmespath 'items' --pretty --file document.json
jmespath --pretty --query-file query.jmespath --file document.json
```

Recognize only the full `--pretty` name, with no short alias or value.
Reject repeated `--pretty` options, missing query sources, and unsupported option combinations with status 2.
Reject `--pretty` combined with syntax validation before reading stdin or opening either input file.
Preserve standalone help and version behavior, exact option matching, delimiter handling, and caller ownership of `argv`.

Preserve the exact two-argument form `--validate EXPRESSION`, including flag-like expressions.
Thus `jmespath --validate --pretty` validates the literal expression `--pretty`; it does not select an output mode.
An actual combination, such as `--pretty --validate --query-file query.jmespath`, is a usage failure.

## Formatting and diagnostics

Evaluate the complete query before selecting `JSON.generate` or `JSON.pretty_generate`.
Retain `JSON.generate` for default output, byte for byte.
Use `JSON.pretty_generate` defaults, including two-space indentation, without changing object key order.
Write the complete serialized result followed by one final newline.
Support objects, arrays, strings, numbers, booleans, Unicode, and null.
Scalars remain valid JSON values.

Reuse the diagnostic renderer from issue #23.
Preserve error text, source excerpts, line numbers, character columns, carets, and exit statuses.
Keep stdout empty on usage, input, syntax, and evaluation failures before output starts.
Do not catch unrelated application exceptions.

Neither raw output nor JSON Lines processing is part of this change.
Their feature issues must reject combinations with `--pretty` when those modes are implemented.

## Verification and documentation

Add focused failing regression tests before implementation.
Assert exact pretty output and parse it to verify equivalence with the query result.
Assert exact compact output for every JSON type.
Cover argument order, source combinations, repeated options, unsupported values, validation conflicts, and unchanged `argv`.
Verify rejected combinations leave stdin and input files untouched.
Compare compact and pretty failure results for malformed JSON, syntax, type, arity, unknown-function, and invalid-value errors.
Include multiline and Unicode query-file diagnostics and verify both executable names.

Update CLI help, the README, and the errors guide with the output and conflict rules.
Update private RBS declarations and YARD comments where signatures or descriptions change.
Preserve imported compliance fixtures and public Ruby signatures.
Run `bundle exec rake` and `bundle exec rake docs`.

Private helper signatures and test organization remain builder decisions.
