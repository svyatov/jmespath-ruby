# Syntax diagnostics implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose an optional syntax formatter with query excerpts, carets, and honest fallbacks for unknown locations.

**Architecture:** Keep structured metadata on `Errors::SyntaxError` and presentation in `JMESPath::Diagnostic`. Reuse lexer and parser byte offsets. Return strings without reading documents or changing automatic exception rendering.

**Tech Stack:** Ruby 3.3+, standard library, existing RSpec, RBS/Steep, and YARD tooling.

**Spec:** [Approved syntax diagnostics design](../specs/2026-11-01-syntax-diagnostics-design.md).

## Global constraints

Preserve exception ancestry, constructor calls, `message`, `expression`, `position`, `line`, and `column` behavior.
Expand tabs to four-column stops and count Unicode code points, without terminal display-width detection.
Keep query syntax, evaluation behavior, imported fixtures, CLI rendering, and CLI help unchanged.
Add no dependencies or input-document access.
Require 100% line and branch coverage and CRAP scores at most 10 per measurable library method.

## Review focus

- R1: Explicit position zero on an empty source must differ from an omitted position.
- R2: Offsets within multibyte characters must produce reason-only output.
- R3: A final LF must retain an empty final excerpt line.
- R4: Control escapes and tabs must use the same transformation for excerpt and caret indentation.
- R5: Formatting must remain a pure operation even after repeated calls and caller mutation of constructor strings.

## File structure

| File | Responsibility |
| --- | --- |
| `lib/jmespath/errors.rb` | Preserve compatibility and store reason and location provenance |
| `lib/jmespath/diagnostic.rb` | New public formatter with private rendering helpers |
| `lib/jmespath.rb` | Load the formatter after errors |
| `sig/jmespath.rbs` | Public accessors and formatter declarations |
| `sig/internal/diagnostic.rbs` | Private helper declarations if required by Steep |
| `spec/unit/errors_spec.rb` | New structured metadata regression tests |
| `spec/unit/diagnostic_spec.rb` | New formatter contract and integration tests |
| `docs/guides/errors.md` | Public usage, fallback behavior, and alignment limitation |

### Task 1: Preserve syntax metadata and distinguish unknown locations

**Files:** Modify `lib/jmespath/errors.rb` and `sig/jmespath.rbs`; create `spec/unit/errors_spec.rb`.

**Interfaces:** Consume the existing constructor. Produce `SyntaxError#reason -> String` and `SyntaxError#location_known? -> bool`.

- [x] **Step 1: Add failing metadata regression tests.**

```ruby
it "distinguishes an omitted offset from explicit zero" do
  unknown = JMESPath::Errors::SyntaxError.new("Bad query")
  known = JMESPath::Errors::SyntaxError.new("Bad query", expression: "", position: 0)
  expect([unknown.location_known?, known.location_known?]).to eq([false, true])
  expect([unknown.position, known.position]).to eq([0, 0])
  expect([unknown.message, known.message]).to eq(["Bad query at byte 0"] * 2)
  expect([unknown.line, unknown.column]).to eq([1, 1])
end

it "owns the reason and expression independently of caller mutation" do
  reason = +"Bad query"
  source = +"'✓' $"
  error = JMESPath::Errors::SyntaxError.new(reason, expression: source, position: 6)
  reason.replace("changed")
  source.clear
  expect(error.reason).to eq("Bad query")
  expect(error.expression).to eq("'✓' $")
  expect([error.position, error.line, error.column]).to eq([6, 1, 5])
  expect(error).to be_a(JMESPath::Errors::Error)
  expect(error).to be_a(StandardError)
end
```

- [x] **Step 2: Run `bundle exec rspec spec/unit/errors_spec.rb`.** Expect failure because the accessors are missing.
- [x] **Step 3: Implement the two accessors and constructor provenance.**

Use a private omission sentinel for `position:` so explicit zero remains distinct from the omitted default.
Keep the public default value zero, store an independent frozen reason, and preserve the exception message exactly.
Update public RBS and YARD declarations without advertising the sentinel as a public value.
Leave lexer, parser, and compiled-expression call sites unchanged because their explicit and omitted positions encode the required distinction.

- [x] **Step 4: Run `bundle exec rspec spec/unit/errors_spec.rb spec/unit/lexer_spec.rb spec/unit/parser_spec.rb spec/unit/boundaries_spec.rb`.** Expect zero failures.
- [x] **Step 5: Commit only this task's files.** Use `feat(errors): expose syntax diagnostic metadata`.

### Task 2: Format diagnostics and document the public contract

**Files:** Create `lib/jmespath/diagnostic.rb` and `spec/unit/diagnostic_spec.rb`; modify `lib/jmespath.rb`, `sig/jmespath.rbs`, and `docs/guides/errors.md`.
Create `sig/internal/diagnostic.rbs` only if private helper declarations are required.

**Interfaces:** Consume Task 1's metadata and existing error coordinates. Produce `JMESPath::Diagnostic.format(error: Errors::SyntaxError) -> String`, with a positional Ruby argument.

- [x] **Step 1: Add failing formatter contract tests.**

Use a helper that compiles a source and returns the rescued `Errors::SyntaxError`.
Assert complete output strings with literal expected coordinates and spacing, independent of formatter helpers.

```ruby
it "formats end of input without a trailing newline" do
  error = syntax_error("items[?active")
  expect(JMESPath::Diagnostic.format(error)).to eq(
    "Expected rbracket, received eof at line 1, column 14\nitems[?active\n             ^"
  )
end

it "expands tabs without changing character coordinates" do
  error = syntax_error("\t'✓' $")
  expect(JMESPath::Diagnostic.format(error)).to eq(
    "Unexpected character at line 1, column 6\n    '✓' $\n        ^"
  )
end
```

Add cases with these fixed expectations:

| Input or condition | Required assertion |
| --- | --- |
| `foo = bar` | Unexpected character, line 1, column 5, four spaces before caret |
| `'unfinished` | Unterminated quoted value, line 1, column 1, caret at opening quote |
| Empty query | Expected an expression, line 1, column 1, empty excerpt, caret at start |
| `foo\n$` | Unexpected character, line 2, column 1, excerpt `$` |
| `foo.\n` | Expected a field, function, or multiselect after dot, line 2, column 1, empty final excerpt, caret at start |
| Repeated tabs before `$` | Each tab advances to the next four-column stop |
| Combining marks and wide characters before an error | One indentation column per code point |
| Explicit negative, out-of-range, or split-code-point position | Reason only, without caret or coordinates |
| Explicit byte zero on empty source versus omitted position | Full diagnostic versus reason only |
| Invalid UTF-8 and binary input rejected by the lexer | Reason only, valid UTF-8 output |
| Valid manually supplied non-UTF-8 source | Convert a private copy if possible, preserving original byte-offset interpretation |
| CRLF source and embedded carriage return | LF delimits lines; render CR as `\r` |
| NUL, ESC, and DEL within a source line | Visible escapes, with caret indentation matching rendered prefix |
| A tab after an escaped control | Tab stop calculated from the rendered excerpt column |
| Parser and literal nesting failures | Use the explicit position supplied by the lexer or parser |
| Compiled query searched with a smaller nesting limit | Reason only because its precise position is unknown |

For R5, call the formatter twice and assert equal output and unchanged error fields.
Assert formatting produces no stdout or stderr output and invokes no `Input.load`, `IO.read`, or `File.read` operation.
Use a source and synthetic document with different marker strings; verify only the query marker can appear.

- [x] **Step 2: Run `bundle exec rspec spec/unit/diagnostic_spec.rb`.** Expect failure because `JMESPath::Diagnostic` is missing.
- [x] **Step 3: Implement `JMESPath::Diagnostic.format(error)` and load it from `lib/jmespath.rb`.**

Validate location provenance, source encoding, byte range, and character boundary before calculating coordinates.
Interpret byte offsets in the stored source before any UTF-8 conversion.
Return the reason alone for unusable locations; never append the compatibility message's byte suffix.
Use private helpers for excerpt selection and shared tab/control rendering; do not add configurable modes.
Escape C0 controls and DEL, retaining tabs as expanded spaces and LF as the line delimiter.
Return UTF-8 with no trailing newline and leave the exception and source untouched.
Add public RBS and YARD declarations, plus private declarations required by Steep.

- [x] **Step 4: Run `bundle exec rspec spec/unit/errors_spec.rb spec/unit/diagnostic_spec.rb spec/integration/cli_spec.rb`.** Expect zero failures and unchanged CLI behavior.
- [x] **Step 5: Update `docs/guides/errors.md` with an executable formatter example.**

Explain known and unknown locations, byte offsets, code-point columns, four-column tabs, control escaping, and terminal alignment limits.
Replace the guide's implication that character columns represent terminal display positions.
Include a YARD example using an explicitly positioned exception and a literal expected diagnostic string.

- [x] **Step 6: Run `bundle exec rake`.** Expect successful lint, types, specs, 100% line and branch coverage, CRAP, and documentation checks.
- [x] **Step 7: Run `bundle exec rake docs`.** Expect YARD generation without warnings.
- [x] **Step 8: Run `bundle exec rake package:check`.** Verify the added formatter and declarations are included by the gemspec's path patterns.
- [x] **Step 9: Commit only this task's files.** Use `feat(diagnostics): format syntax excerpts and carets`.

## Handoff

Recommend native execution because both tasks share one small error contract and the second directly consumes the first.
Read the approved spec before execution and preserve unrelated untracked files.
Review the complete diff against this plan after verification, before proposing integration.

## Implementation evidence

Implemented on `feat/syntax-diagnostics` with MRI 4.0.9.
The full gate passed with 4,033 examples, 100% line and branch coverage, lint, RBS/Steep, CRAP, and executable documentation.
YARD generation and offline package installation passed.
The gem contains the formatter, error metadata, public signatures, and updated errors guide.
