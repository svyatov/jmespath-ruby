# CLI function listing

Status: proposed for approval.
Scope: [issue #26](https://github.com/svyatov/jmespath-ruby/issues/26).

## Intent and boundaries

Let terminal users discover built-in function names, accepted arguments, and descriptions through `jmespath --functions`.
This is a small change shared by `jmespath` and `jmespath.rb`.
Preserve default query behavior, standard JMESPath semantics, and the public Ruby API.
Exclude custom registries, Ruby file loading, return types, machine-readable output modes, dependencies, and unrelated CLI refactoring.
Shell completion belongs to [issue #27](https://github.com/svyatov/jmespath-ruby/issues/27).
That issue completes option names and filenames; it does not consume this listing or complete expressions.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| O1: One line per function, with signature and description | Compact terminal reference | Long entries can wrap in narrow terminals | Selected by the user |
| O2: Signature and description on separate lines | Separates long descriptions | Doubles the number of lines | Not selected |

The user selected O1.
The exact notation and argument rules below are proposals for approval.

## Listing format

Read sorted names from `JMESPath::Functions.default.names`.
Read each function's public metadata through `metadata(name)`.
Print every default-registry function exactly once, in that order.
Preserve argument order and union order from metadata.
Copy descriptions from metadata without rewriting them.
Use one space between the closing parenthesis and description, without padding, colors, or terminal-width detection.
Terminate every entry with a newline.

These entries illustrate the proposed output:

```text
abs(number) Absolute value.
join(string, array<string>) Join strings with a separator.
length(string|array|object) Character or element count.
merge(object...) Merge objects, with later values winning.
sort(array<number>|array<string>) Stable sorted array of numbers or strings.
```

Join argument types with `|` and arguments with comma-space.
Render `array_number` as `array<number>` and `array_string` as `array<string>`.
Render other type symbols by name, including `any` and `expref`.
Append `...` to the final argument when `variadic?` is true.
Parenthesize a variadic union before appending `...`, such as `(string|null)...`.
Show zero-argument signatures as `name()`.
These formatting rules describe metadata; they do not infer runtime constraints or return types.

After the entries, print one blank line and this legend:

```text
Types: any accepts any value; A|B accepts either type.
array<T> requires every element to have type T; array is unrestricted.
expref is an expression reference, written &expression.
T... requires one or more arguments of type T.
Signatures describe declared argument types; runtime checks can be narrower.
```

## Argument and diagnostic contract

Accept only standalone `--functions`, without a short alias or value.
Return status 0 with the listing on stdout and empty stderr.
Do not access stdin, query files, document files, or function implementations.
Leave caller-owned streams and `argv` unchanged.

Reject repetitions, values, positional queries, query files, document files, and combinations with other modes or information flags.
Return status 2 with empty stdout and usage guidance on stderr.
Include the standalone listing form in that guidance.
Reject invalid combinations before accessing input files or stdin.
Preserve exact option matching, delimiter handling, help, and version behavior.
After `--`, treat `--functions` as query text under the ordinary query rules.

Preserve the exact two-argument form `--validate EXPRESSION`, including flag-like expressions.
Thus `--validate --functions` validates literal query text and does not request a listing.
Actual mode combinations, including `--functions --validate` and `--validate --functions --query-file PATH`, fail with status 2.
Reuse the CLI's handling of output failures, including status 1 for handled I/O errors.
Do not catch unrelated application exceptions.

## Verification and documentation

Add focused failing regression tests before implementation.
Verify every default-registry name appears once in lexical order.
Compare signatures and descriptions with public metadata and independently assert representative complete output lines.
Cover unions, homogeneous arrays, expression references, variadic arguments, and the legend.
Use a reader that raises on access to prove stdin stays unread.
Verify listing does not invoke functions or open input files.
Cover help, rejected combinations, exact diagnostics, statuses, argument ownership, delimiters, and literal validation compatibility.
Verify successful listing and usage failures through both executable names while stdin remains open.

Update CLI help, the README, and the functions guide with executable shell examples and notation.
Update affected private RBS declarations and YARD descriptions without adding a public Ruby API.
Preserve imported compliance fixtures.
Run `bundle exec rake` and `bundle exec rake docs`.
Private helper boundaries and test organization remain builder decisions.
