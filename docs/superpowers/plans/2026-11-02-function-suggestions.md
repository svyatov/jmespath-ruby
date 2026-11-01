# Unknown function suggestions implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Suggest up to three registered names when function lookup fails.

**Architecture:** Keep lookup and suggestion ownership in `Functions`. Use a private matcher for optimal string alignment distance. Store immutable results on `UnknownFunctionError`, whose message also serves the CLI.

**Tech Stack:** Ruby 3.3+, RSpec, RBS, Steep, YARD, and installed development tools. No added dependencies.

**Spec:** [Approved design](../specs/2026-11-02-function-suggestions-design.md).

## Global constraints

- Match case-sensitively against names in the active registry.
- Allow one edit when the longer name has at most four characters, and two edits otherwise.
- Rank qualifying candidates by ascending edit distance, then ascending lexical order.
- Return at most three distinct names; empty registries and unrelated names produce an empty array.
- Preserve argument evaluation order and runtime name resolution.
- Successful calls avoid suggestion matching.
- Preserve custom registry dispatch and imported compliance fixtures.
- Unknown-function failures remain visible with `disable_visit_errors: true`.
- Automatic correction, global registries, compilation-time availability checks, and additional dependencies are outside scope.
- Preserve the unrelated untracked `oss-audit-report.md`.

## Review focus

- R1: A shared compiled query uses each search's registry without caching suggestions from another registry. Test in Task 2.
- R2: An argument callback failure retains identity and prevents outer-name inspection. Test in Task 2.
- R3: Case-only differences count as edits; matching must not lowercase identifiers. Test in Task 1.
- R4: Overlapping edits distinguish optimal string alignment from unrestricted swap distance. Test in Task 1.
- R5: Long custom identifiers with incompatible lengths are rejected before distance calculation. Test in Task 1.

## File map

| File | Responsibility |
| --- | --- |
| `lib/jmespath/functions/suggestions.rb` | Private name ranking and distance calculation |
| `sig/internal/suggestions.rbs` | Private matcher types |
| `lib/jmespath.rb` | Require matcher before use |
| `lib/jmespath/functions.rb` | Invoke matcher only on lookup failure |
| `lib/jmespath/errors.rb` | Immutable fields and readable suggestion suffix |
| `sig/jmespath.rbs` | Public error constructor and readers |
| `spec/unit/function_suggestions_spec.rb` | Matching and direct registry failures |
| `spec/unit/errors_spec.rb` | Error construction and ownership |
| `spec/integration/function_suggestions_spec.rb` | Execution order, dispatch, and registry isolation |
| `spec/integration/cli_spec.rb` | Error text, help, and exit status |
| `lib/jmespath/cli.rb` | Explain typo suggestions in help |
| `docs/guides/errors.md`, `docs/guides/functions.md` | Public behavior and executable examples |

### Task 1: Suggest names on registry lookup failure

**Interfaces:**

- Consume `Functions#names() -> Array[String]` without executing callbacks.
- Add internal `Functions::Suggestions.for(name, names) -> Array[String]`, marked `@api private`.
- Add private singleton `distance(left, right) -> Integer` within the matcher.
- Add `UnknownFunctionError.new(message = nil, function_name: nil, suggestions: [])`.
- Expose `function_name -> String?` and `suggestions -> Array[String]` as immutable snapshots.
- Preserve `Functions#call` and `#call_with_context` signatures.

- [x] **Step 1: Add direct-call regression examples.**

Use `registry.call` failures to assert exact suggestions and messages, including these cases:

| Query name | Registered candidates | Expected suggestions |
| --- | --- | --- |
| `lenght` | Built-ins | `["length"]` |
| `dobule` | `double` | `["double"]` |
| `abxc` | `abc` | `["abc"]` |
| `abc` | `abxc` | `["abxc"]` |
| `abxd` | `abcd` | `["abcd"]` |
| `abxy` | `abcd` | `[]` |
| `abcxy` | `abcde` | `["abcde"]` |
| `abxyz` | `abcde` | `[]` |
| `abcx` | `abcd`, `abcxx` | `["abcd", "abcxx"]` |
| `abcx` | `abce`, `abca`, `abcd`, `abcb` | `["abca", "abcb", "abcd"]` |
| `abcx` | `abxx`, `abcxyy` | `["abxx", "abcxyy"]` |
| `ABCD` | `abcd` | `[]` |
| `Abcd` | `abcd` | `["abcd"]` |
| `CAxyz` | `ABCxyz` | `[]` |
| `zzzzzzzz` | Built-ins or empty registry | `[]` |

Register candidates with blocks that raise if executed. Override `length` and assert `lenght` suggests it exactly once.
For R5, register a 1,000-character identifier against `abc`; assert no suggestions and no distance invocation.
Assert a successful registered call never invokes `Suggestions.for`.

- [x] **Step 2: Add error ownership and compatibility examples.**

Assert `UnknownFunctionError.new("manual").message == "manual"`, nil `function_name`, and frozen empty `suggestions`.
Also exercise construction without a positional message and preserve the inherited default message when suggestions are absent.
Mutate caller-owned names, arrays, and candidate strings after construction; assert stored values remain unchanged and deeply frozen.
Assert caller-owned inputs remain mutable.
Assert exact messages for zero, one, and three suggestions, including punctuation and ranking.
Assert the error remains a `RuntimeError` and an `Errors::Error`.

- [x] **Step 3: Run the regression tests before implementation.**

Run `bundle exec rspec spec/unit/function_suggestions_spec.rb spec/unit/errors_spec.rb`.
Confirm failures concern missing fields or suggestions, not fixture setup.

- [x] **Step 4: Implement error data and private matching.**

Use three dynamic-programming rows for optimal string alignment, with adjacent swaps costing one edit.
Reject candidates whose length difference exceeds their threshold before calculating distance.
Sort qualified `[distance, name]` pairs, take three, and return their names.
Keep helpers private and mark the matcher `@api private`.
On `Functions#invoke` lookup failure, pass the failed name and ranked names to `UnknownFunctionError`.
Preserve `Unknown function: NAME` without suggestions; append `. Did you mean NAME1, NAME2?` when present.
Copy and freeze structured data in the error constructor.
Add public RBS and YARD declarations alongside implementation; add private matcher RBS declarations.

- [x] **Step 5: Verify direct registry behavior and commit.**

Run the Step 3 command plus `bundle exec rspec spec/unit/functions_spec.rb spec/unit/function_metadata_spec.rb`.
Run `bundle exec rake types`.
Expect passing examples and type checks.
Commit only Task 1 files with `feat(functions): suggest registered names on lookup failure`.

### Task 2: Verify execution boundaries and document diagnostics

**Interfaces:** Consume Task 1 error readers and messages through unchanged query and CLI APIs.

- [x] **Step 1: Add integration tests for registry selection and evaluation order.**

Run each scenario through configured compiled execution and explicit `Evaluator` execution, using the repository's parser helpers.
Assert compiling `dobule(@)` succeeds without resolving availability.
Use one cached expression with distinct registries containing `double` and `dobble`; assert each failure suggests only its registry's name.
Verify both saved registries and search-time registry overrides.
Repeat concurrent searches with those registries and assert isolated arrays.
For `lenght(first(), second())`, record callback events followed by name inspection; expect exactly that order and count.
Have `first()` raise a sentinel error; assert identical exception identity and no outer-name inspection or second callback.
Assert unknown errors remain visible with suppression enabled.
Verify a registry subclass overriding `call` retains its return value and receives no forced suggestion lookup.
Preserve a callback-raised `UnknownFunctionError` instance, message, metadata, and backtrace.

- [x] **Step 2: Add CLI regression tests.**

Assert `cli(["lenght(name)"], '{"name":"Ada"}')` returns `[1, "", "Unknown function: lenght. Did you mean length?\n"]`.
Assert `zzzzzzzz()` retains `Unknown function: zzzzzzzz\n` and exit status 1.
Assert help mentions suggestions without reading JSON input.

- [x] **Step 3: Run integration tests and confirm the help assertion fails.**

Run `bundle exec rspec spec/integration/function_suggestions_spec.rb spec/integration/cli_spec.rb`.
The query assertions should pass using Task 1; help should fail until updated.
Investigate any execution-order failure before changing dispatch code.

- [x] **Step 4: Update help and public documentation.**

Add a concise help sentence explaining registered-name suggestions for unknown functions.
Document edit operations, length thresholds, case sensitivity, lexical tie-breaking, and the three-result cap in the functions guide.
Document immutable `function_name` and `suggestions`, manual construction defaults, runtime resolution, and message behavior in the errors guide.
Include executable examples asserting `lenght` yields `["length"]` and the exact message.
Keep `Diagnostic.format` scoped to syntax errors.

- [x] **Step 5: Verify the complete change.**

Run `bundle exec rake` and `bundle exec rake docs`; require both to pass.
Use `Open3.capture3` with the installed Ruby and each repository executable to verify the typo message and status 1.
Run the repository prose checker on touched documentation and `git diff --check`.
Review the diff for changed imported fixtures, unrelated files, or public suggestion APIs beyond the approved error fields.

- [x] **Step 6: Commit documentation and integration coverage.**

Commit only Task 2 files with `feat(cli): document unknown function suggestions`.
Report verified behavior and the command `bundle exec ruby exe/jmespath 'lenght(name)'` with JSON supplied on standard input.
Remote publication and pull request creation require separate authorization.

## Verification record

Implemented on `feat/function-suggestions`.
The initial unit regression run failed for missing suggestion data and matching.
The CLI help regression failed before the help update.
`bundle exec rake` passed 4,143 examples with 100% line and branch coverage, lint, RBS, Steep, CRAP, and documentation checks.
`bundle exec rake docs` generated YARD documentation without YARD warnings.
The prose checker and `git diff --check` passed.
