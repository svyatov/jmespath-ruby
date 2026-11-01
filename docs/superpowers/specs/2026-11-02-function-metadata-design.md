# Function metadata

## Intent and scope

Expose immutable metadata for functions in an active registry, as requested by [issue #24](https://github.com/svyatov/jmespath-ruby/issues/24).
The first consumer is [issue #25](https://github.com/svyatov/jmespath-ruby/issues/25), which needs registered names for typo suggestions.
Implement suggestions separately.

## Approaches

The user selected A1: a sorted name collection plus metadata lookup by name.
A2, a sorted metadata collection, requires consumers to extract names and search records.
A3, a hash of metadata keyed by name, couples lookup and enumeration to a public collection structure.
A1 serves name-only consumers directly while providing a small, explicit lookup interface.

## Public contract

`Functions#names` returns a frozen array of frozen strings in ascending, case-sensitive lexical order.
An empty registry returns an empty frozen array.

`Functions#metadata(name)` accepts a string and returns a `Functions::Metadata` record, or `nil` for an absent name.
The record exposes `name`, `signature`, `variadic?`, and `description`.
Its signature uses the same nested arrays of type symbols accepted by `Functions#with`, including unions and typed arrays.
For variadic signatures, the final declared argument repeats and remains required.
Metadata describes declared argument types; it does not encode all runtime constraints or infer return types.

`Functions#with` gains an optional `description: nil` keyword.
A description must be a string or `nil`; invalid values raise `ArgumentError`.
Copy and freeze supplied strings without freezing the caller's objects.
Provide a concise, nonempty description for every built-in function.
An override replaces the entire definition, including its description; omitting the description yields `nil`.

Freeze records and all nested values.
Later registrations and changes to caller-owned strings or signature arrays cannot change previously returned metadata.
Do not promise object identity across inspection calls.

## Constraints and implementation choices

Keep implementations, handlers, private signature objects, and registry storage outside the public record.
Inspection must neither execute callbacks nor modify registries.
Concurrent inspection of a shared registry must be safe without mutable lazy caches.
Preserve function execution, registration defaults, evaluation order, and JMESPath compatibility.
Use existing dependencies and preserve imported fixtures.

The proposed record name, absent-name behavior, description validation, and override semantics are design choices for approval.
The builder may choose eager snapshots or fresh immutable results, provided these contracts hold.
Keep signature metadata derived from the validated definition rather than duplicating signature rules.

## Validation and documentation

Add regression tests before implementation for built-ins, empty registries, custom functions, overrides, unions, typed arrays, and variadic definitions.
Test deep immutability, caller-owned input mutation, deterministic ordering, callback isolation, and concurrent reads.
Update public and internal RBS signatures, YARD documentation, and the functions guide with executable examples.
No CLI flag or output change is included because this issue adds a Ruby inspection API.
Run `bundle exec rake` and `bundle exec rake docs`.
