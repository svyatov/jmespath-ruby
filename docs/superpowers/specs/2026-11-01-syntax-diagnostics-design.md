# Syntax diagnostics

Status: proposed for approval.
Scope: [issue #13](https://github.com/svyatov/jmespath-ruby/issues/13).

## Intent

Help Ruby callers locate syntax failures without manually finding a byte offset in their query.
Keep structured error data separate from presentation.
This is a small change using the library's Ruby conventions and dependencies.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| A1: `JMESPath::Diagnostic.format(error)` | Separates formatting from error data | Adds a public module | Selected by the user |
| A2: `error.diagnostic` | Discoverable on the exception | Couples error data to presentation | Not selected |

The user selected character-based caret placement, with tabs expanded to four-column stops.
Terminal display-width calculation was rejected because it adds Unicode width rules and terminal-dependent behavior.

## Public contract

`JMESPath::Diagnostic.format(error)` accepts `JMESPath::Errors::SyntaxError` and returns a UTF-8 string without a trailing newline.
It is available after `require "jmespath"`.
It neither prints output nor accepts an input document.

For `JMESPath.compile("items[?active")`, formatting the rescued exception returns:

```text
Expected rbracket, received eof at line 1, column 14
items[?active
             ^
```

The output contains the reason, one-based line and character column, one source line, and one caret.
There are no line-number gutters, colors, configurable styles, or surrounding context lines.

Preserve exception ancestry, constructor calls, `message`, `expression`, `position`, `line`, and `column` behavior.
Add `SyntaxError#reason` to expose the original reason without its byte-offset suffix.
Add `SyntaxError#location_known?` to distinguish an explicit source location from the constructor's default byte zero.
These two accessors are proposed implementation choices, subject to approval of this document.

An omitted constructor position keeps the public `position` value zero but marks the location unknown.
An explicitly supplied zero can identify the beginning of an expression, including an empty expression.
The formatter uses structured fields, never parsing `message` to recover the reason or location.

## Source and caret rules

Positions remain zero-based byte offsets into the expression stored by the exception.
Line and column remain one-based, with Unicode code points defining character columns.
Formatting never changes the stored expression or position.

Expand tabs in the excerpt to the next four-column stop, counting from the start of the source line.
Calculate caret indentation using the same transformation of the prefix before the failure.
Count each Unicode code point as one column, without combining-mark, emoji, or wide-character adjustment.
Document that terminal alignment can differ from this rule.

Use LF to delimit source lines, consistent with the error's line calculation.
Render other control characters as visible escapes and account for their rendered lengths when placing the caret.
This prevents query text from injecting extra lines or terminal control sequences into the excerpt.

At end of input, place the caret immediately after the final character.
For a trailing LF, show the empty final line with the caret at its start.
An empty expression has an empty excerpt and a caret at line 1, column 1.
Unterminated literals point to the opening quote, matching their reported byte offset.

If the source encoding is unusable, the location is unknown, or the offset is invalid, return only the reason.
Reject negative offsets, offsets beyond the source, and offsets inside a multibyte character as unusable locations.
Do not infer a precise location from a default offset.

Parser nesting failures retain the token location reported by the parser.
Compiled-expression nesting failures without a precise location produce reason-only output.
Invalid-encoding errors also produce reason-only output.

## Scope and constraints

Keep query syntax, evaluation behavior, imported fixtures, CLI rendering, and CLI help unchanged.
The issue's explicit CLI exclusion takes precedence over its generic instruction to update CLI help.
Add no dependencies, input-document access, automatic exception rendering, or terminal width detection.
A misleading caret or disclosure of input data is a failure even when formatting otherwise succeeds.

Private helper structure and file organization remain implementation decisions.
Keep those helpers private and verify behavior through the public formatter.

## Verification and documentation

Add focused regression tests before implementation.
Cover malformed operators, unterminated literals, empty expressions, multiline queries, end-of-input failures, tabs, Unicode, invalid encodings, and nesting limits.
Cover invalid offsets, control-character escaping, unknown locations, unchanged error attributes, and repeated formatting without mutation.
Verify formatting never reads or prints an input document.
Document the formatter, fallback behavior, and character-counting limitation in the errors guide.
Update public RBS declarations and YARD documentation, including an executable usage example.
Run `bundle exec rake` and `bundle exec rake docs` after implementation.
Verify packaged assets if implementation changes package contents beyond the gemspec's included paths.
