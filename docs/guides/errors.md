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
The formatter adds no colors and preserves exception messages.
The CLI uses it to render syntax failures.

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

## Syntax validation

Use `JMESPath.validate` in Ruby to check syntax without an input document:

```ruby
JMESPath.validate("items[*].name") #=> []
diagnostics = JMESPath.validate("items[?active")
failure = diagnostics.fetch(0)
failure.reason #=> "Expected rbracket, received eof"
failure.expression #=> "items[?active"
failure.position #=> 13
failure.line #=> 1
failure.column #=> 14
failure.location_known? #=> true
JMESPath::Diagnostic.format(failure) #=> "Expected rbracket, received eof at line 1, column 14\nitems[?active\n             ^"
```

The result is a frozen array containing zero or one immutable `JMESPath::SyntaxDiagnostic` record.
Parsing stops at the first syntax failure.
Records contain frozen copies of the reason and expression, without an exception or backtrace.
Source text and coordinates match compilation errors, including the lexer's conversion to UTF-8.
Positions are zero-based byte offsets; lines and Unicode character columns are one-based.
For unknown locations, `position`, `line`, and `column` are nil, and `location_known?` is false.
Invalid encodings produce an unlocated diagnostic with an empty stored expression.
The formatter accepts both records and syntax errors and applies the same excerpt and caret rules.

Validation neither evaluates data nor invokes callbacks, checks function availability, builds execution plans, or uses the compilation cache.
Unknown functions, incorrect argument counts, and unsupported runtime argument types remain valid syntax.
Validation cannot establish whether a query will succeed for a function registry or input document.
Parser failures other than `SyntaxError` propagate, including `InvalidValueError` for a zero slice step, matching compilation.

The only option is `max_depth:`, an Integer from 1 through 128, defaulting to 128.
Invalid expression types, depth values, and unsupported keywords raise `ArgumentError` before parsing.

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

## Unknown function data

Library-owned `UnknownFunctionError` failures expose `function_name` and `suggestions`.
The name identifies the missing function; suggestions contain up to three ranked names from the active registry.
The name, suggestion strings, and suggestions array are immutable copies.
Use these fields instead of parsing the error message.

Use this Ruby example to inspect a misspelled function:

```ruby
error = begin
  JMESPath.search("lenght(name)", {name: "Ada"})
rescue JMESPath::Errors::UnknownFunctionError => failure
  failure
end
error.function_name #=> "lenght"
error.suggestions #=> ["length"]
error.message #=> "Unknown function: lenght. Did you mean length?"
```

Messages retain `Unknown function: NAME` when no similar names exist.
Otherwise, they append `. Did you mean NAME1, NAME2?` using the ranked suggestions.
The CLI prints this message and exits with status 1.
`Diagnostic.format` accepts syntax errors; unknown-function diagnostics use `error.message`.
See [matching rules](functions.md#unknown-function-suggestions) for thresholds and ranking.

Lookup remains part of evaluation and follows argument evaluation.
Unsuppressed argument failures take precedence over a missing outer function, including callback failures when visit errors are disabled.
Unknown-function failures are not suppressed by `disable_visit_errors`.
Callback exceptions retain their identity, backtrace, and metadata.
Manually constructed errors default to a nil `function_name` and empty `suggestions`; positional message construction remains supported.

Invalid JSON streams raise the JSON parser's error class.
Invalid options raise ArgumentError.

## CLI diagnostics

Both `jmespath` and `jmespath.rb` print expected input and query failures to stderr and exit with status 1.
Failures before output starts leave stdout empty.
Successful queries print one JSON result to stdout.
Usage failures print usage to stderr and exit with status 2 without reading stdin.
Help and version requests exit with status 0 without reading stdin.
With `--file PATH`, usage failures and informational requests do not open the document.
Missing or unreadable document files produce escaped operating-system messages on stderr with status 1.
File failures leave stdin unused, and files opened by the CLI close after parsing, including when parsing fails.
Query diagnostics retain their source locations when JSON comes from a file.

Select a saved UTF-8 query with `--query-file PATH` and supply the document through stdin or `--file PATH`.
Query files retain their source text, including Unicode, line breaks, and trailing newlines.
Syntax and function diagnostics use that text for their excerpts, coordinates, and carets.
An empty file produces an empty-expression syntax diagnostic with status 1.
Missing or unreadable query files produce escaped operating-system messages with status 1, leaving document input untouched.
Query files close after reading, including read failures, before document input is accessed.
After the query file is read, malformed JSON takes precedence over query syntax errors.
Absent or conflicting query sources, repeated options, and missing values produce usage failures before opening files.

To execute a saved query, run this command in a shell:

```sh
jmespath --query-file query.jmespath --file document.json
```

To query a UTF-8 document file, run this command in a shell:

```sh
jmespath --file document.json 'length(@)'
```

Both executables also support validation without reading stdin.
Run this command in a shell:

```sh
jmespath --validate 'items[*].name'
jmespath --validate --query-file query.jmespath
```

Valid syntax leaves both output streams empty and exits with status 0.
Unknown functions remain valid syntax; function availability and runtime types require evaluation.
For invalid syntax, the command prints a formatted diagnostic to stderr and exits with status 1.
Parser value failures, including a zero slice step, also exit with status 1.
Missing or excess validation arguments print usage to stderr and exit with status 2.
Every validation outcome leaves stdout empty and does not read stdin.
In the exact two-argument form `--validate EXPRESSION`, the second argument is query text, even when it resembles a flag.
Thus `--validate --query-file` validates the literal expression `--query-file`.
File validation also accepts `--query-file PATH --validate` and rejects `--file`.

To inspect a function type failure, run this command in a shell:

```sh
printf '%s\n' '4' | jmespath 'length(@)'
```

The command exits with status 1 and prints this diagnostic to stderr:

```text
Invalid argument 1 for length: expected string, array, or object; received number at line 1, column 1
length(@)
^
```

Syntax failures show the reason, coordinates, query line, and caret through `Diagnostic.format`.
Function type failures report the argument position, expected types, and received type.
Expression-reference failures identify the rejected expression result and its argument position.
Arity failures report the expected and received counts, with `at least` marking a variadic minimum.

Type and arity carets identify the start of the failing function call, including nested calls.
They do not identify the exact invalid argument.
The CLI uses the formatter's character columns, tab expansion, and visible control escapes.
Wide characters, emoji, and combining marks can display differently from character-based caret alignment.
Missing or unusable source ranges omit coordinates, the query line, and the caret.
Incomplete validation metadata retains the escaped exception message and any usable source location.
Unknown-function diagnostics retain suggestions; invalid-value failures use message-only diagnostics.

Malformed JSON from stdin or a file prints `Invalid JSON input` without parser messages or document fragments.
For example, run this command in a shell:

```sh
printf '%s\n' '{"private_marker":BROKEN}' | jmespath '@'
```

The command prints `Invalid JSON input` to stderr, leaves stdout empty, and exits with status 1.
Stream and operating-system failures retain escaped messages.
Diagnostics add no colors, application backtraces, or input-document values.
Unrelated application exceptions propagate.
