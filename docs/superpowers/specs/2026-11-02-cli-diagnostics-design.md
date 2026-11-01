# Readable CLI diagnostics

Status: awaiting design approval.
Scope: [issue #23](https://github.com/svyatov/jmespath-ruby/issues/23).

## Intent and scope

Help CLI users locate query failures and understand function validation failures without inspecting Ruby exceptions.
This is a small change covering one positional query, stdin JSON, and both executables.
Future CLI modes remain assigned to their feature issues.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| O1: Query location and failure details | Locates failures in nested queries | Requires source rendering and metadata fallbacks | Selected by the user |
| O2: Failure details only | Keeps diagnostics compact | Leaves users to locate the failing call | Not selected |

The implementation proposal uses private CLI formatting helpers and preserves the public syntax formatter's contract.
Shared private rendering helpers may serve syntax and runtime diagnostics without adding public Ruby interfaces.

## Presentation

Syntax failures use `JMESPath::Diagnostic.format(error)`.
Type and arity failures use structured metadata, without parsing exception messages or inspecting document values.
Type failures identify the function, argument position, expected types, and actual type.
Expression-reference failures explicitly identify the rejected expression result and its argument position.
Render homogeneous arrays as `array of strings` or `array of numbers`, and unions as readable type lists.
Arity failures identify the function, expected count, and received count.
Variadic signatures describe the expected count as a minimum.

When usable source metadata exists, append coordinates, the query line, and a caret at the function call's start.
The caret identifies the function call, not the exact invalid argument.
For `length(@)` with JSON input `4`, the proposed stderr output is:

```text
Invalid argument 1 for length: expected string, array, or object; received number at line 1, column 1
length(@)
^
```

Use the original query and byte range without additional parsing or evaluation.
Reuse syntax diagnostics' Unicode character columns, four-column tab stops, visible control escapes, and location validation.
Invalid or missing source metadata omits the coordinates, excerpt, and caret.
Incomplete validation metadata falls back to the exception message, retaining usable source context when available.

Unknown-function failures retain their messages, including suggestions supplied by issue #25.
Invalid-value failures retain their messages without invented source locations.
Escape control characters in message-only diagnostics to prevent terminal escape sequences and injected lines.
Add no colors, flags, backtraces, input values, or document excerpts.

## Input failures and compatibility

Malformed JSON produces `Invalid JSON input` on stderr with status 1.
This deliberately replaces parser messages that can contain document fragments.
Expected stream and operating-system failures retain escaped messages and status 1.
Usage failures retain status 2 and do not read stdin.
Help and version requests retain status 0 and do not read stdin.
Successful JSON output, parsing order, exception messages, and query semantics remain unchanged.
Failures before output starts leave stdout empty.
Do not catch arbitrary application exceptions or add dependencies.

## Verification and documentation

Write focused failing regression tests before implementation.
Cover syntax, type, arity, expression-reference, unknown-function, and invalid-value failures through positional queries.
Cover nested calls, Unicode, tabs, controls, multiline positional queries, and absent or unusable metadata.
Verify exact stderr, exit statuses, empty stdout, suggestion preservation, and document-fragment exclusion.
Exercise both executables with successful queries, expected failures, and usage failures.
Verify unrelated application exceptions propagate.
Update CLI help and the errors guide, including the caret limitation and generic JSON error.
Update private RBS declarations as needed; preserve public RBS and YARD contracts.
Run `bundle exec rake` and `bundle exec rake docs`.

Private helper names, file organization, and ordinary grammatical details remain implementation decisions.
