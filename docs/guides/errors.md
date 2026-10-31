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
This distinguishes byte offsets from Unicode display positions.

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
