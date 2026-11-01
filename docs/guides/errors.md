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

## Function validation data

Library-owned `InvalidTypeError` and `InvalidArityError` failures expose immutable metadata.
Read these fields directly instead of parsing the message.

| Field | Meaning |
| --- | --- |
| `function_name` | Identifier of the failing function |
| `signature` | Complete declared signature as arrays of accepted type symbols |
| `variadic?` | Whether the final declared argument repeats |
| `source_range` | Exclusive range of zero-based byte offsets for the function call, or nil for direct calls |

Use this Ruby example to inspect a type failure:

```ruby
error = begin
  JMESPath.search("join(',', names)", {names: [1, 2]})
rescue JMESPath::Errors::InvalidTypeError => failure
  failure
end
error.function_name #=> "join"
error.signature #=> [[:string], [:array_string]]
error.argument_position #=> 2
error.expected_types #=> [:array_string]
error.actual_type #=> :array
error.validation_stage #=> :argument
error.source_range #=> (0...16)
```

Type errors expose `argument_position`, `expected_types`, `actual_type`, and `validation_stage`.
Argument positions start at one, including trailing variadic arguments.
Type symbols match function registration: `:array_number` and `:array_string` describe homogeneous arrays.
An accepted-types array describes a union; empty arrays satisfy both homogeneous-array constraints.
For homogeneous-array element failures, `expected_types` retains the declared array constraint and `actual_type` describes the outer array.
Metadata includes no element values or indices.

The declared `signature` describes all arguments; `expected_types` describes the specific failing check.
For example, `contains` accepts any second argument in its signature but requires a string when searching a string.
`validation_stage` distinguishes an `:argument` failure from an `:expression_result` failure.
Functions such as `sort_by` require expression results to be numbers or strings of one consistent type.
After the first valid result, `expected_types` contains only that result's type.
An error inside a referenced function identifies that inner function and its source range.

Arity errors expose `expected_arity` and `actual_arity`.
`expected_arity` is exact unless `variadic?` is true, when it is the minimum count.
Use this Ruby example for a direct call without source context:

```ruby
error = begin
  JMESPath::Functions.default.call("merge", [])
rescue JMESPath::Errors::InvalidArityError => failure
  failure
end
error.function_name #=> "merge"
error.expected_arity #=> 1
error.actual_arity #=> 0
error.variadic? #=> true
error.source_range #=> nil
```

Offsets refer to the original query's bytes, including bytes before multibyte characters.
Metadata contains no argument values or input documents.
Diagnostics preserve adapter conversion order and counts.
`actual_type` is `:unknown` when identifying a more specific type would require another adapter conversion.
Manually constructed errors can have nil metadata; application exceptions retain their identity, backtrace, and original metadata.
Custom registry overrides of `Functions#call` retain their dispatch contract and may raise errors without source context.

Invalid JSON streams raise the JSON parser's error class.
Invalid options raise ArgumentError.
The CLI translates expected input failures to status 1 and usage failures to status 2.
