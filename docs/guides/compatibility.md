# Compatibility

The package is named `jmespath-ruby`. It provides `require "jmespath"` and `JMESPath.search`.
Select one JMESPath provider in an application bundle.

A dependency on the package named `jmespath` does not resolve to `jmespath-ruby` automatically.
Dependencies that declare that name need their own dependency change before replacing the provider.
Loading both providers in one process is unsupported because their require paths and constants overlap.

## Ruby inputs

Search accepts hashes with string or symbol keys, arrays, JSON scalars, Structs, Pathname, IO, and StringIO.
Objects implementing `to_hash`, `to_ary`, or `to_str` use explicit conversion boundaries.
A malformed conversion raises TypeError; exceptions from application conversion methods propagate.

String keys with non-nil values take precedence over matching symbol keys.
A nil string-key value allows lookup of an existing symbol key.
Queries never create symbols or invoke arbitrary Struct methods.
Selected values preserve their Ruby object identity.
Constructed arrays, hashes, and literal values belong to each search result.

Stream input starts at the current position and remains open after the search.
Pathname input is opened and closed by the library.
Invalid JSON retains the JSON parser's error class.

## Options and errors

The third positional argument remains an options hash; keyword options are also accepted.
Conflicting duplicate options and unknown option names raise ArgumentError.
Supported options are `cache_expressions`, `disable_visit_errors`, `functions`, and `max_depth`.

The named error classes remain under `JMESPath::Errors`.
Function validation errors can use subclasses of InvalidTypeError and InvalidArityError.
Error message wording and private parser objects are outside the compatibility contract.
Function names resolve during evaluation so compiled expressions can use different custom registries.

With `disable_visit_errors: true`, library argument-type and arity failures return nil.
Syntax, invalid-value, unknown-function, conversion, and application callback failures still raise.
A callback's exception object and backtrace remain intact.

## Deliberate corrections

| Behavior | Result |
| --- | --- |
| Surplus arguments to `reverse` | InvalidArityError |
| Missing or surplus arguments to `to_array` | InvalidArityError |
| `min_by` or `max_by` on an empty array | nil |
| Invalid trailing variadic arguments | InvalidTypeError |
| Indexes beyond native machine integer range | nil, without a Ruby RangeError |

Legacy bare backtick literals and ordering between strings remain supported.
Numeric operations accept finite integers and floats; non-finite values are outside the JSON number domain.
Cyclic values raise InvalidValueError when structural comparison or serialization encounters the cycle.

## Limits

Expression nesting defaults to 128 and can be reduced with `max_depth`.
The maximum supported setting is 128.
Nested arrays and objects in JSON literals count toward this limit.
Compiled searches also check literal depth when a caller requests a lower limit.
Flat field chains use iterative evaluation and do not consume that nesting budget per field.
The compilation cache holds at most 256 entries and 1,048,576 source bytes.
Oversized expressions bypass caching without becoming invalid.

## Verification

Pinned fixture sources are recorded with SHA-256 hashes in `spec/fixtures/upstream/sources.json`.
Python reference: `2812594e69d43098ef60f81f4efc404c071b0418`.
Ruby reference: `5e86ea7da2e954cc12f5b3a8383a43c0a65acba7`.

Both compliance corpora run with plain inputs and supported Ruby wrappers.
Error cases also run with visit-error suppression enabled.
Benchmark-only cases use separate expectations where the upstream file omits a result.
Imported fixture bytes remain unchanged.

Differential verification checked 1,192 distinct and generated cases against both references.
There were no unexpected differences.
The two accepted differences were Ruby's empty-array errors for `min_by` and `max_by`.

To repeat the comparison with the pinned library checkouts:

```sh
bundle exec ruby script/differential.rb --python-root /path/to/python --ruby-root /path/to/ruby
```
