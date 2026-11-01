# Unknown function suggestions

## Intent and scope

Help developers identify misspelled function names, as requested by [issue #25](https://github.com/svyatov/jmespath-ruby/issues/25).
Suggest names from the active registry, including custom functions.
Preserve argument evaluation order and runtime name resolution.
Automatic correction, global registries, compilation-time availability checks, and additional dependencies are outside scope.

## Approaches

The user selected A1: count insertion, deletion, replacement, and an adjacent letter swap as one edit each.
A2 counts only insertion, deletion, and replacement, making `lenght` two edits from `length` and admitting weaker matches at that distance.
A1 treats common typing mistakes directly.

The user selected O1: expose structured suggestions and append them to the exception message.
O2 preserves messages and extends `Diagnostic.format`, requiring separate CLI integration and making suggestions less visible.
O1 uses the CLI's message output without extending the syntax formatter.

## Matching contract

Match case-sensitively against names in the active registry.
Allow one edit when the longer name has at most four characters, and two edits otherwise.
Rank qualifying candidates by ascending edit distance, then ascending lexical order.
Return at most three distinct names; empty registries and unrelated names produce an empty array.
Overrides contribute one candidate under the registered name.

My proposed implementation choice is optimal string alignment distance, which supports adjacent swaps without editing the same substring twice.
Compute matches only after registry lookup fails, using callback-free name inspection.
Keep matcher helpers private and avoid mutable caches shared between registries.

## Error and message contract

`UnknownFunctionError` exposes `function_name` and `suggestions`.
Copy and freeze the name, suggestion strings, and suggestions array without freezing caller-owned values.
Preserve positional message construction; manually constructed errors default to a nil name and empty suggestions.
Library errors retain the prefix `Unknown function: NAME`.
When suggestions exist, append `. Did you mean NAME1, NAME2?`, using ranked names.
For example: `Unknown function: lenght. Did you mean length?`.
Without suggestions, preserve the complete original message.

## Compatibility and implementation boundaries

Both compiled execution and interpreted evaluation evaluate arguments before looking up the outer function.
Argument failures and callback effects retain their order and identity.
Unknown-function failures remain visible with `disable_visit_errors: true`.
Successful calls avoid suggestion matching.
Preserve custom registry dispatch and imported compliance fixtures.
The builder chooses private helper layout and distance computation details within these contracts.

## Validation and documentation

Add focused regression tests before implementation.
Cover built-ins, custom functions, overrides, empty registries, case sensitivity, all edit types, threshold boundaries, lexical ties, and the three-result limit.
Verify registry isolation, deep immutability, callback-free inspection, and argument evaluation order across execution paths and direct calls where applicable.
Update public RBS, YARD, executable guide examples, and CLI help.
Verify CLI error text and unchanged exit status 1.
Run `bundle exec rake` and `bundle exec rake docs`.
