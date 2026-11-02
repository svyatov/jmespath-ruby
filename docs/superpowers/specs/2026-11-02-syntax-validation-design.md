# Syntax validation

Status: proposed for approval.
Scope: [issue #28](https://github.com/svyatov/jmespath-ruby/issues/28).

## Intent and scope

Let forms, editors, and shell scripts validate query syntax without providing an input document.
This is a small change that adds a Ruby interface and a CLI validation mode.
Preserve compilation, search, standard syntax, and imported compliance fixtures.
Schema checks, function availability checks, type checks, automatic corrections, and parser recovery are outside scope.

## Approaches

The user selected A1: call the parser directly and convert syntax failures into immutable diagnostics.
This reuses syntax rules and nesting limits without building execution plans or changing the compilation cache.
A2 wraps `compile`, which needs less code but builds execution plans and uses cache capacity during validation.

## Ruby interface

Add `JMESPath.validate(expression, max_depth: 128)` after `require "jmespath"`.
Return a frozen array: empty for valid syntax, or containing one `JMESPath::SyntaxDiagnostic` for the first syntax failure.
The parser stops at the first failure; returning an array does not promise multiple diagnostics.
Parse through the same parser and lexer used by compilation, without evaluation or function lookup.
Unknown functions and invalid runtime argument types or counts remain valid syntax.

Require a String expression and an Integer `max_depth` from 1 through 128.
Validate method arguments before parsing.
Invalid expression types, depth values, and unsupported keywords raise `ArgumentError`, even when the expression also contains syntax errors.
Accept no function registry, evaluation policy, input document, or cache option.
Rescue only `JMESPath::Errors::SyntaxError`; unrelated exceptions propagate.

## Diagnostic record

Add an immutable `JMESPath::SyntaxDiagnostic` record with `reason`, `expression`, `position`, `line`, `column`, and `location_known?`.
Copy diagnostic data from the parser's syntax error, without retaining its exception or backtrace.
Freeze the record and its strings without freezing caller-owned strings.
Later changes to the supplied expression cannot change a returned diagnostic.

Use the error's stored expression and zero-based byte offset for located failures.
That expression follows the lexer's UTF-8 conversion, matching compilation errors.
Line and column are one-based; columns count Unicode code points.
Unknown locations use nil for `position`, `line`, and `column`, with `location_known?` returning false.
Invalid-encoding failures retain the error's reason and stored expression, without invented coordinates.
Preserve the compatibility behavior of `SyntaxError`, including its default zero position.

Extend `JMESPath::Diagnostic.format` to accept either a syntax error or a syntax diagnostic.
Reuse its source excerpt, caret, tab, control-character, and unknown-location rules.
Return UTF-8 text without a trailing newline.
The formatter continues to perform no input reads or output writes.

## CLI behavior

Both executables accept `--validate EXPRESSION`, with exactly one expression after the flag.
Validation never reads stdin or evaluates data.
Success leaves stdout and stderr empty and returns status 0.
A syntax failure leaves stdout empty, prints the formatted diagnostic to stderr, and returns status 1.
Incorrect validation usage prints usage to stderr and returns status 2 without reading stdin.
Treat the token following `--validate` as the expression, including tokens that resemble flags.
Preserve the single-expression search command and its behavior.
Update usage and help with the validation form and its syntax-only limitation.
JSON output, extra flags, stdin query input, and configurable nesting limits for the CLI are outside scope.

## Verification and documentation

Add focused regression tests before implementation.
Cover valid syntax, malformed queries, invalid encodings, Unicode, multiline queries, end-of-input failures, and nesting boundaries.
Check syntax acceptance against `compile`, including unknown functions and expressions that fail only during evaluation.
Verify callbacks are never executed, compilation plans are never built, and validation does not use the compilation cache.
Test deep immutability, caller-owned string mutation, and invalid method arguments.
Test both executables, output streams, exit statuses, and validation with stdin that fails if read.
Update public and internal RBS, YARD, the errors guide, and CLI help with executable examples where applicable.
Use existing dependencies and run `bundle exec rake` and `bundle exec rake docs`.
Verify packaged assets if implementation changes package contents beyond the gemspec's included paths.

## Proposed choices and builder discretion

The record name, fields, nil coordinates, formatter extension, and exact CLI behavior are proposed choices for approval.
Private helper structure, record construction, and file organization remain implementation decisions.
No product implementation starts before approval of this document.
