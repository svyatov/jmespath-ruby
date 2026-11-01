# Errors and diagnostics

The common base class is `JMESPath::Errors::Error`.
SyntaxError derives from that base; evaluation errors derive from RuntimeError.

| Error | Meaning |
| --- | --- |
| `SyntaxError` | Invalid expression syntax, encoding, or nesting |
| `InvalidTypeError` | Unsupported argument or expression-key type |
| `InvalidArityError` | Incorrect number of function arguments |
| `InvalidValueError` | Invalid slice step or cyclic value during structural processing |
| `UnknownFunctionError` | Function absent from the supplied registry |

SyntaxError exposes the expression, a zero-based byte position, and one-based line and character column.
Character columns count Unicode code points, independently of byte offsets and terminal display widths.

Use `JMESPath::Diagnostic.format(error)` to get the reason, source coordinates, query line, and caret as a string.
The formatter returns UTF-8 without a trailing newline and does not print output or read an input document.
For example, rescue a compilation failure and format it:

```ruby
error = begin
  JMESPath.compile("items[?active")
rescue JMESPath::Errors::SyntaxError => failure
  failure
end
JMESPath::Diagnostic.format(error) #=> "Expected rbracket, received eof at line 1, column 14\nitems[?active\n             ^"
```

The resulting diagnostic is:

```text
Expected rbracket, received eof at line 1, column 14
items[?active
             ^
```

`error.reason` returns the failure reason without the byte-offset suffix in `error.message`.
`error.location_known?` reports whether an explicit source position was supplied.
An omitted position retains the compatibility value zero but does not identify a precise failure location.
An explicitly supplied zero identifies the beginning of the expression, including an empty expression.

For unknown locations, unusable encodings, and invalid byte offsets, the formatter returns only the reason.
Invalid offsets include negative values, values beyond the expression, and positions within a multibyte character.
Invalid-encoding failures and compiled-expression nesting failures without a precise location use this fallback.
End-of-input failures place the caret after the last character, or on an empty final line after a trailing LF.

The excerpt expands tabs to four-column stops and escapes other C0 controls and DEL.
The formatted reason uses the same escaping, including visible escapes for embedded line breaks.
The stored reason and exception message retain their original text.
LF separates source lines; a carriage return appears as `\r`.
Caret indentation follows the rendered prefix, including tab expansion and visible escapes.
Each Unicode code point counts as one column.
Combining marks, emoji, and wide characters can therefore display differently from the caret's character-based alignment.
The formatter adds no colors and does not change exception messages or CLI output.

Runtime failures use the error classes below:

```ruby
JMESPath.search("length(@)", 7) # raises JMESPath::Errors::InvalidTypeError
JMESPath.search("unknown()", {}) # raises JMESPath::Errors::UnknownFunctionError
JMESPath.search("[::0]", []) # raises JMESPath::Errors::InvalidValueError
JMESPath.search("length(@)", 7, disable_visit_errors: true) #=> nil
```

Only library argument-type and arity failures are suppressed by `disable_visit_errors`.
Syntax, unknown-function, invalid-value, adapter, and callback failures remain visible.
Missing fields and out-of-range indices normally return nil.

Invalid JSON streams raise the JSON parser's error class.
Invalid options raise ArgumentError.
The CLI translates expected input failures to status 1 and usage failures to status 2.
