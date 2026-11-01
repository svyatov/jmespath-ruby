# Function metadata implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose immutable function names and metadata from the active registry for issue #24.

**Architecture:** Keep registry lookup and registration in `Functions` and validation in its private `Signature` class. Return fresh immutable inspection results without lazy caches. Store descriptions alongside validated signatures and implementations, and expose only public metadata records.

**Tech Stack:** Ruby 3.3+, RSpec, RBS, Steep, YARD, and the existing Rake tasks.

**Spec:** [Approved design](../specs/2026-11-02-function-metadata-design.md).

## Global constraints

- Use existing dependencies and preserve imported fixtures.
- Preserve function execution, registration defaults, evaluation order, and JMESPath compatibility.
- Inspection must neither execute callbacks nor modify registries.
- Freeze records and all nested values.
- Implement suggestions separately.
- No CLI flag or output change is included because this issue adds a Ruby inspection API.

## Review focus

- R1: Mutating supplied names, descriptions, or signature arrays cannot alter stored metadata.
- R2: An override without a description clears the inherited description and preserves the parent registry.
- R3: Mixed-case names use case-sensitive lexical order, independent of registration order.
- R4: Concurrent reads and derived registrations do not expose names from another registry.
- R5: Returned records expose neither implementations nor private signature objects.

## Task 1: Add registry inspection and custom descriptions

**Files:** Modify `lib/jmespath/functions.rb`, `lib/jmespath/functions/signature.rb`, `sig/jmespath.rbs`, and `sig/internal/functions.rbs`. Create `spec/unit/function_metadata_spec.rb`.

**Interfaces:** Consume validated `Signature` instances and immutable `@definitions`. Produce `Functions#names -> Array[String]`, `Functions#metadata(String) -> Functions::Metadata?`, and optional `description: String?` on `Functions#with`. Records expose `name: String`, `signature: Array[Array[Symbol]]`, `variadic? -> bool`, and `description: String?`.

- [ ] **Step 1: Add failing inspection tests.** Include these assertions with a callback that raises if invoked:

```ruby
registry = JMESPath::Functions.new.with(
  "sample", signature: [[:string, :null], [:array_number]],
  variadic: true, description: "Read sample values."
) { raise "Inspection invoked callback" }
metadata = registry.metadata("sample")
expect(registry.names).to eq(["sample"])
expect(metadata.name).to eq("sample")
expect(metadata.signature).to eq([[:string, :null], [:array_number]])
expect(metadata.variadic?).to be(true)
expect(metadata.description).to eq("Read sample values.")
expect(registry.metadata("missing")).to be_nil
```

Add empty-registry and zero-argument cases, omitted descriptions, `:array_string`, and every level of freezing.
Assert mutation raises `FrozenError` for the names array, name strings, signature arrays, and description strings.
Reject non-string descriptions such as `false`, `42`, and `:text` with `ArgumentError`; accept `nil` and empty strings.
Cover R1 with mutable inputs changed after registration, while confirming registration leaves caller-owned inputs unfrozen.
Cover R2 with both explicit and omitted replacement descriptions, then inspect the retained parent snapshot.
Cover R3 by registering `z`, `a`, and `A` and expecting `["A", "a", "z"]`.
Cover R4 using threads that inspect one registry and independently derive registries with distinct names; propagate failures with `Thread#value`.
Cover R5 by checking the public record surface and confirming `signature` contains arrays, without handlers or callback fields.

- [ ] **Step 2: Run the tests before implementation.**

Run: `bundle exec rspec spec/unit/function_metadata_spec.rb`.
Expected: failures for missing inspection methods and the unsupported description keyword.

- [ ] **Step 3: Implement the inspection contract.**

Add a small frozen `Functions::Metadata` record in `functions.rb`, with the four public readers defined above.
Expose immutable argument arrays and variadic state through private-class `Signature` readers; do not expose the `Signature` instance publicly.
Extend private `Definition` with a description, defaulting built-in descriptions to `nil` until Task 2.
Validate, copy, and freeze custom descriptions before storing them.
Have `names` sort frozen definition keys into a frozen array.
Have `metadata(name)` build a deeply immutable record from the matching definition, returning `nil` when absent.
Keep inspection allocation outside the execution path and leave `FunctionCall` unchanged.
Update public and internal RBS definitions alongside the Ruby changes.
Document public methods and record fields with YARD types.

- [ ] **Step 4: Verify the implementation and type declarations.**

Run `bundle exec rspec spec/unit/function_metadata_spec.rb spec/unit/functions_spec.rb spec/unit/signature_spec.rb`, `bundle exec rbs -I sig validate`, and `bundle exec steep check`.
Expected: zero failures and no type errors.

- [ ] **Step 5: Commit only Task 1 files.**

Use `feat(functions): expose immutable registry metadata`.

## Task 2: Describe built-ins and document inspection

**Files:** Modify `lib/jmespath/functions/scalar.rb`, `lib/jmespath/functions/collections.rb`, `lib/jmespath/functions.rb`, `sig/internal/functions.rbs`, `spec/unit/function_metadata_spec.rb`, and `docs/guides/functions.md`.

**Interfaces:** Consume Task 1 inspection methods. Extend private `with_builtin` with `description: String`, and provide a nonempty description for every built-in.

- [ ] **Step 1: Add failing built-in tests.** Assert the complete expected list of 26 built-in names in lexical order, independently of registration constants.

```ruby
registry = JMESPath::Functions.default
expect(registry.metadata("join").signature).to eq([[:string], [:array_string]])
expect(registry.metadata("sort").signature).to eq([[:array_number, :array_string]])
expect(registry.metadata("merge").variadic?).to be(true)
expect(registry.metadata("not_null").variadic?).to be(true)
expect(registry.metadata("length").variadic?).to be(false)
registry.names.each do |name|
  expect(registry.metadata(name).description).to be_a(String).and satisfy { |text| !text.strip.empty? }
end
```

Also override a built-in in a derived registry and verify its parent retains the original description and behavior.

- [ ] **Step 2: Run the built-in tests before implementation.**

Run: `bundle exec rspec spec/unit/function_metadata_spec.rb`.
Expected: failures because built-in descriptions are `nil`.

- [ ] **Step 3: Add descriptions and executable guide examples.**

Keep description text adjacent to each module's registrations, using the functions guide's result descriptions as the starting point.
Pass descriptions through private `with_builtin`, using the same copying and freezing policy as custom registration.
Document metadata fields, absent-name behavior, ordering, immutable snapshots, typed arrays, unions, variadic signatures, and override semantics.
Include executable examples for custom descriptions, `names`, `metadata`, a built-in description, and a missing name.
State that metadata covers declared arguments and does not encode every runtime constraint.

- [ ] **Step 4: Run the full required checks.**

Run `bundle exec rake` and `bundle exec rake docs` without output filters.
Expected: successful lint, RBS, Steep, tests, coverage, complexity, documentation checks, and YARD generation.
Run the oss-writing prose checker on the changed guide and `git diff --check`.
Expected: zero findings and no whitespace errors.

- [ ] **Step 5: Commit only Task 2 files.**

Use `feat(functions): describe built-in metadata and inspection`.
