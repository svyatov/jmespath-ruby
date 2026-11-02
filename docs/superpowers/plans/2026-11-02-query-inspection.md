# Compiled query inspection implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add immutable, structured query explanations through `Expression#explain`, without evaluating input or resolving functions.

**Architecture:** Preserve syntax and execution as private implementation details. A private translator converts syntax into the approved logical tree with named child roles and preorder IDs. Parser metadata distinguishes implicit identities from explicit source expressions.

**Tech Stack:** Ruby 3.3+, RSpec, RBS, Steep, YARD, and installed benchmark tools. No added dependencies.

**Spec:** [Approved design](../specs/2026-11-02-query-inspection-design.md).

## Global constraints

- Keep syntax nodes, compiled closures, and optimizer decisions private.
- Preserve search behavior, options, dependencies, and imported fixtures.
- Add `JMESPath::Expression#explain` with no arguments.
- The top-level keys are `:source` and `:root`.
- All nodes have exactly five keys: `:id`, `:operation`, `:source_range`, `:details`, and `:children`.
- Each child entry has exactly two keys: `:role` and `:node`.
- Keys use symbols; operation names and child roles use strings.
- Assign consecutive integer IDs starting at zero by preorder traversal of the public tree.
- Represent source ranges as `[start_byte, end_byte]`, with an inclusive start and exclusive end.
- Offsets refer to the returned UTF-8 `:source`, consistent with lexer offsets and function-error byte ranges.
- Use nil for synthetic operations without their own complete source expression.
- Freeze every nested hash, array, and string, including literal values and literal object keys.
- Ordinary compile and search must not build or retain a public explanation unless inspection requests it.
- Exclude execution traces, schema inference, function validation, readable text rendering, and a CLI inspection flag.
- Preserve the unrelated untracked `oss-audit-report.md`.

## Review focus

- R1: Convertible non-UTF-8 text retains `Expression#source` while explanation offsets address returned UTF-8 text. Test in Task 2.
- R2: Long flat chains remain shallow and inspectable without stack overflow. Test in Tasks 1 and 2.
- R3: Literal object keys and decoded strings cannot expose mutable explanation data. Test in Task 2.
- R4: Inspection remains equal across saved registries, error policies, cache settings, and concurrent calls. Test in Task 2.
- R5: Metadata repairs preserve function-error locations, syntax diagnostics, nesting limits, and callback order. Test in both tasks.

## File map

| File | Responsibility |
| --- | --- |
| `lib/jmespath/ast.rb` | Private indication of synthetic syntax |
| `lib/jmespath/parser.rb` | Node construction and source bounds |
| `lib/jmespath/parser/expressions.rb` | Explicit expression bounds |
| `lib/jmespath/parser/projections.rb` | Implicit identities and projection bounds |
| `sig/internal/parser.rbs` | Parser and syntax metadata types |
| `spec/unit/parser_spec.rb` | Explicit versus synthetic positions and nesting regressions |
| `lib/jmespath/explanation.rb` | Private translation into public explanation data |
| `lib/jmespath/expression.rb` | Public `explain` method and YARD contract |
| `lib/jmespath.rb` | Load the translator |
| `sig/jmespath.rbs` | Public recursive data types and method declaration |
| `sig/internal/explanation.rbs` | Private translator declarations |
| `spec/integration/query_inspection_spec.rb` | Public schema, vocabulary, ordering, ownership, and isolation |
| `spec/integration/query_inspection_ranges_spec.rb` | Public source coordinate contract |
| `docs/guides/compilation.md`, `README.md` | Public documentation and executable examples |

## Execution preparation

Use the worktree skill before implementation if isolation is needed.
Preserve a clean pre-Task-1 checkout for the benchmark reference; record its commit and absolute path.
Keep benchmark reports in a scratch directory outside either checkout.

### Task 1: Establish reliable private source metadata

**Interfaces:**

- Consume `Parser.new(source, max_depth: 128).parse -> AST::Node`.
- Add private `AST::Node#synthetic? -> bool`, defaulting to false in the constructor.
- Extend `Parser#node` and `AST::Node.new` with `synthetic: false`.
- Preserve integer `start` and `finish` metadata for diagnostic and execution callers.
- Task 2 uses `synthetic?` to return nil ranges without changing AST evaluation semantics.

- [x] **Step 1: Add failing parser metadata examples.**

Add examples in `spec/unit/parser_spec.rb` with these explicit assertions:

```ruby
explicit = parse("@")
expect(explicit.synthetic?).to be(false)
expect([explicit.start, explicit.finish]).to eq([0, 1])

index = parse("[0]")
expect([index.start, index.finish]).to eq([0, 3])
expect(index.children.fetch(0).synthetic?).to be(true)

projection = parse("items[*]")
expect([projection.start, projection.finish]).to eq([0, 8])
expect(projection.children.fetch(1).synthetic?).to be(true)
```

Cover implicit identities in `*`, `[]`, `[::]`, and `[?active]`, plus absent projection right-hand expressions.
Assert every implicit identity is synthetic and every explicit `@` is not synthetic.
Assert explicit bounds for `(@)`, `!active`, `&name`, `items[].name`, and `{key: value}` entries.
Retain the 2,000-field chain depth assertion and the exact 128/129 nesting acceptance tests for R2 and R5.

- [x] **Step 2: Run metadata tests before implementation.**

Run `bundle exec rspec spec/unit/parser_spec.rb`.
Expect failures for missing `synthetic?`, plus any inaccurate explicit ranges exposed by the assertions.

- [x] **Step 3: Add synthetic metadata and repair explicit ranges.**

Define `synthetic?` and the constructor keyword in `lib/jmespath/ast.rb`.
Pass the keyword through `Parser#node` in `lib/jmespath/parser.rb`.
Mark parser-created implicit `current` nodes as synthetic in `lib/jmespath/parser/projections.rb`.
Leave explicit `prefix_current` nodes non-synthetic.
Repair explicit bounds in the parser only where the approved range rules require it.
Keep parser binding powers, child ordering, depth calculation, and semantic node kinds unchanged.
Update `sig/internal/parser.rbs` with matching constructors, instance metadata, and helper declarations.

- [x] **Step 4: Verify parser and diagnostic compatibility.**

Run `bundle exec rspec spec/unit/parser_spec.rb spec/unit/diagnostic_spec.rb spec/unit/boundaries_spec.rb spec/integration/function_validation_context_spec.rb spec/integration/compilation_spec.rb`.
Run `bundle exec rake types`.
Require passing examples and type checks, including exact function-error ranges and unchanged callback counts.

- [x] **Step 5: Commit the metadata change.**

Stage only Task 1 files.
Commit with `refactor(parser): identify implicit source expressions`.

### Task 2: Expose and document the immutable logical explanation

**Interfaces:**

- Consume Task 1 syntax metadata, `Expression#source`, and private `Expression` root syntax.
- Add private `Explanation.build(source, root) -> explanation` in `lib/jmespath/explanation.rb`, marked `@api private`.
- Add `Expression#explain() -> explanation`, delegating to a fresh translator on every call.
- Declare public RBS aliases `explanation`, `explanation_node`, `explanation_child`, and `explanation_details`.
- Use exact records for node and child shapes; use the existing `json` alias for literal data.
- Keep node IDs and traversal state local to one build, without memoization or changes to execution plans.

The public RBS aliases have these shapes:

```rbs
type explanation_details = Hash[Symbol, json]
type explanation_child = { role: String, node: explanation_node }
type explanation_node = {
  id: Integer,
  operation: String,
  source_range: [Integer, Integer]?,
  details: explanation_details,
  children: Array[explanation_child]
}
type explanation = { source: String, root: explanation_node }
```

- [x] **Step 1: Add failing public schema and vocabulary tests.**

In `spec/integration/query_inspection_spec.rb`, assert the complete `user.name` hash from the approved design.
Use independently written expectations, not translator constants or private AST traversal.
Add examples whose operation names, details, and child roles cover every row of the design's vocabulary table.
For `items[?active].name | sort(@)`, assert filter roles are `["input", "condition", "expression"]` and pipe children use `"step"`.
Assert preorder IDs across the complete result equal consecutive integers beginning at zero.
For comparisons, assert `operation == "comparison"` and the exact operator for all six comparisons.
Cover `items[1:5:2]`, `items[::-1]`, and `[::]` with explicit and nil slice components.
Cover multiselects, duplicate hash keys, explicit groups, literals, short-circuit operators, and deferred expression references.
Keep duplicate hash entries in source order even when their names match.
Assert literal arrays and objects remain literal values rather than explanation children.
Assert a 2,000-field chain produces 2,000 `step` children without stack overflow, satisfying R2.

- [x] **Step 2: Add failing public source-range tests.**

In `spec/integration/query_inspection_ranges_spec.rb`, assert exact ranges and extracted substrings for these examples:

| Source | Assertions |
| --- | --- |
| `user.name` | Root `[0, 9]`, field children `[0, 4]` and `[5, 9]` |
| `  user.name  ` | Root `[2, 11]`; explanation source retains both surrounding spaces |
| `items[?active].name` | Root `[0, 19]`, input `[0, 5]`, condition `[7, 13]`, expression `[15, 19]` |
| `[0]` | Root `[0, 3]`, implicit input range nil |
| `items[*]` | Root `[0, 8]`, implicit projected expression range nil |
| `(@)` | Group `[0, 3]`, explicit current `[1, 2]` |
| `"café".name` | Root `[0, 12]`, quoted field `[0, 7]`, final field `[8, 12]` |

Add multiline, CRLF, tab, escaped-name, trailing-newline, slice, flatten, hash-entry, and reference cases with literal expected offsets.
Assert each non-nil range stays within the returned source and its substring has valid UTF-8 encoding.
For R1, compile `"'café'".encode(Encoding::UTF_16LE)`.
Assert the explanation source equals UTF-8 `"'café'"`, root range `[0, 7]`, and literal value `"café"`.
Assert the expression's original source encoding and bytes remain unchanged.

- [x] **Step 3: Add failing ownership and non-execution tests.**

Recursively check frozen hashes, arrays, strings, hash keys, operation names, roles, and literal contents, covering R3.
Assert attempted mutation fails, while ordinary literal search results remain independent and mutable.
Round-trip explanations through `JSON.generate` and `JSON.parse`; assert expected string keys, values, and nil ranges.
Assert equality across repeated, cached, uncached, configured, and suppressed-error variants, covering R4.
Run eight threads against one expression and compare every explanation with the independent expected result.
Compile unknown and custom function calls successfully, then install registry spies before calling `explain`.
Assert inspection never invokes `definition`, `metadata`, `names`, `call`, `call_with_context`, or registered callbacks.
Compile a built-in override as well, so inspection cannot silently consult default definitions.
Assert `Expression#explain` rejects positional and keyword arguments with `ArgumentError`.

- [x] **Step 4: Run the public regression tests before implementation.**

Run `bundle exec rspec spec/integration/query_inspection_spec.rb spec/integration/query_inspection_ranges_spec.rb`.
Expect failures for the missing `Expression#explain` method, not parser setup or invalid query syntax.

- [x] **Step 5: Implement translation and public types.**

Implement `Explanation.build(source, root)` and `Expression#explain` using the Task 2 interfaces.
Load the translator from `lib/jmespath.rb` before expressions use it.
Translate private comparison kinds into `comparison` and private pairs into `entry`.
Translate filter children into input, condition, and expression order before assigning IDs.
Use the design table for every operation's exact details and roles.
Convert node bounds into two-element arrays, returning nil for synthetic nodes.
Encode the returned source as UTF-8 without changing `Expression#source`.
Copy and deeply freeze public values, including literal hash keys, without freezing caller-owned values.
Keep arbitrary function names as strings and avoid registry lookup.
Add public recursive RBS records and private translator types in the mapped signature files.
Add YARD documentation and an executable example for `Expression#explain`.

- [x] **Step 6: Document the contract.**

Extend `docs/guides/compilation.md` with the complete schema, operation table, coordinate rules, ID scope, and logical evaluation rules.
State that traversal order is structural, while filters evaluate conditions before projecting selected elements.
Document conditional boolean evaluation, repeated projection evaluation, and deferred expression references.
Document immutable literal values, nil ranges, UTF-8 source normalization, runtime function resolution, and JSON serialization.
Add a short executable README example showing `JMESPath.compile("user.name").explain[:root][:operation] #=> "subexpression"`.
Keep CLI behavior and help unchanged.

- [x] **Step 7: Verify behavior, quality, and performance impact.**

Run the Task 2 focused command, then `bundle exec rake` and `bundle exec rake docs`.
Require all examples, coverage thresholds, lint, types, complexity checks, and documentation checks to pass.
Use the installed benchmark harness against pre-change and candidate checkouts with identical upstream workloads, Ruby settings, iterations, and rounds.
Run `ruby script/benchmark.rb --ruby-root BASELINE_PATH --iterations 1000 --rounds 5 --memory --output REPORT_PATH` with concrete scratch paths.
Preserve its workload/source hashes, runtime metadata, elapsed time, allocations, retained bytes, RSS, peak RSS, and startup results.
Report search, cached, compiled, and churn results separately; churn exercises repeated compilation.
Do not interpret startup as an isolated compile measurement.
Explain metadata costs and investigate material regressions before claiming ordinary-search performance is preserved.
Use installed dependencies only and remove scratch scripts when finished.
Run the repository prose checker on touched documentation and run `git diff --check`.
Run `bundle exec rake package:check` to confirm the translator loads from the packaged gem.
Review the complete diff for imported-fixture edits, unrelated files, and unintended public classes.

- [x] **Step 8: Commit and report the public interface.**

Stage only Task 2 files.
Commit with `feat(expression): explain compiled query structure`.
Report the verified `JMESPath.compile("items[?active].name | sort(@)").explain` interface and any measured performance limitation.
Keep implementation status separate from CI, publication, and release status.

## Self-review

The plan covers every approved operation, source rule, immutability requirement, isolation requirement, and documentation obligation.
R1 through R5 each have explicit tests in their owning tasks.
Task 1 preserves private execution metadata while adding the synthetic distinction consumed by Task 2.
The plan adds no trace events, CLI mode, dependency, or public parser class.
