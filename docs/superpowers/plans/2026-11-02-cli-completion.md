# CLI shell completion implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Package manually installed Bash and Zsh completion for options and filesystem paths through both CLI names.

**Architecture:** Two static shell definitions handle option prefixes, path arguments, and the option delimiter. Tests exercise shell registration and completion through both source files and extracted gem assets. CLI validation remains authoritative for conflicting options.

**Tech Stack:** Bash 3.2+, Zsh 5.9, Ruby 3.3+, RSpec, and Ruby standard-library subprocess and terminal support.

**Spec:** [Approved design](../specs/2026-11-02-cli-completion-design.md).

## Global constraints

Preserve CLI behavior, public Ruby interfaces, and standard JMESPath semantics.
Use Bash built-ins compatible with Bash 3.2 and Zsh's standard completion system, without external frameworks.
Completion must never execute either CLI executable, evaluate queries, or read document or query contents.
Exclude expression completion, Fish support, automatic installation, completion frameworks, and filtering conflicting options.
Cover implemented options at execution time; include `--interactive` only if its implementation has landed.
Keep imported compliance fixtures unchanged and add no dependencies.
Use isolated execution workspace setup before implementation; preserve unrelated work.

## Review focus

R1: A path named `--` is an option value, not an option delimiter.
R2: Bash word splitting around `=` must preserve path completion in ordinary interactive shells.
R3: Spaces and shell metacharacters in filenames must insert one literal argument without executing shell text.
R4: Repeated Tab presses and an empty current word must preserve directory traversal and suppress positional expression completion.
R5: Completion loaded from a gem outside the checkout must work without either executable on PATH.

## File responsibilities

| Files | Responsibility |
| --- | --- |
| Create `completions/jmespath.bash` | Bash registration and completion using built-ins |
| Create `completions/_jmespath` | Zsh registration and completion using standard completion facilities |
| Create `spec/support/shell_completion.rb` | Isolated shell startup, completion probes, terminal cleanup, and bounded waits |
| Create `spec/integration/cli_completion_spec.rb` | Option, filename, registration, and input-isolation regressions |
| Modify `spec/packaging/gem_spec.rb` | Package inclusion and completion from extracted assets |
| Modify `jmespath-ruby.gemspec` | Include both completion definitions |
| Create `docs/guides/completion.md` | Manual installation, shell setup, and usage |
| Modify `README.md` and `lib/jmespath/cli.rb` | Link installation guidance from the CLI documentation and help |

## Task 1: Complete options and literal paths in both shells

**Interfaces:**

Bash defines `_jmespath_completion()`, consuming Readline callback arguments and `COMP_WORDS`, `COMP_CWORD`, `COMP_LINE`, and `COMP_POINT`.
It populates the `COMPREPLY` array and registers through `complete` for both executable names.
Zsh defines `_jmespath()` with no arguments and registers both names through the standard completion system.
Both definitions consume only shell state and filesystem entry names.
The test helper exposes `ShellCompletion.complete(shell:, root:, line:) -> String`, returning the resulting command buffer after Tab.
It also exposes `ShellCompletion.candidates(shell:, root:, line:) -> Array[String]` for complete candidate-set assertions.
`root` identifies the directory containing `completions/`; probe working directories contain test fixtures.
Use real interactive completion for quoting and word-boundary tests; test registration separately in clean shell sessions.

- [x] **Step 1: Write failing shell regressions.**

Create the helper with `Open3`, `PTY`, `Timeout`, and temporary directories using repository test conventions.
Start Bash without profiles and Zsh without user startup files, with an isolated HOME and completion cache.
Bound each probe with a timeout and ensure child processes and terminals close after success or failure.
Load completion through the documented shell registration mechanism, with Zsh initialization using `compinit`.
Report an unavailable shell explicitly through a pending example; execute every installed-shell example.
Independently list expected option spellings from the implemented parser and standalone information flags.
At the approved baseline, these are `-h`, `--help`, `--version`, `--functions`, `--file`, `--query-file`, `--validate`, `--pretty`, `--raw-output`, and `--json-lines`.
Compare that list with registered CLI options, excluding parser-internal rejection patterns and undocumented aliases.
Assert both shell definitions offer exactly this option set for each executable before and after a positional expression.
Assert repeated and conflicting options remain available.
Assert delimiter and positional-expression cases return no candidates.
For each shell and executable, assert these unambiguous completions in isolated fixture directories:
Define an example-local `complete(line:)` wrapper supplying the shell and asset root to `ShellCompletion.complete`.

```ruby
expect(complete(line: "jmespath --que")).to end_with("--query-file ")
expect(complete(line: "jmespath --query-file que")).to include("query.jmespath")
expect(complete(line: "jmespath --file=doc")).to include("document.json")
```

Repeat both path options with separated and equals values, nested directories, spaces, quoted prefixes, and hyphen-leading names.
For R1, complete a later option after `--file --`; compare with suppression after a standalone delimiter.
For R2, retain default Bash word-break settings in equals-value terminal tests.
For R3, insert filenames containing apostrophes, dollar signs, and command-substitution text as literal arguments.
Use a sentinel file to assert command-substitution text never executes.
For R4, complete a unique directory, then its child with a second Tab press; test an empty path prefix.
Test an empty positional prefix separately and assert no filesystem candidates appear.
Put failing stub executables for both command names on PATH and assert they remain uncalled.
Include unreadable query and document fixtures, asserting their names still complete without content access.

- [x] **Step 2: Confirm the regressions fail before implementation.**

Run `bundle exec rspec spec/integration/cli_completion_spec.rb`.
Expect failures caused by missing shell assets or registration, not terminal setup or timeout errors.

- [x] **Step 3: Implement the two shell definitions.**

Create the definitions and registrations specified by the interfaces above.
Track path values and the standalone delimiter without reproducing mode validation.
Use shell-native filename completion with correct candidate boundaries and directory continuation.
Preserve quoted and equals-value forms, including Bash's default word breaks.
Avoid default filename fallback for positional expressions and after the delimiter.
Keep files independent of checkout paths, executables, Ruby, and input contents.

- [x] **Step 4: Verify shell behavior and syntax.**

Run `bash -n completions/jmespath.bash` and `zsh -n completions/_jmespath`.
Run `bundle exec rspec spec/integration/cli_completion_spec.rb`.
Expect successful syntax checks and zero failing examples for installed shells.

- [x] **Step 5: Commit the shell feature.**

Stage only both shell assets and their tests and helper.
Commit with `feat(cli): add Bash and Zsh completion definitions`.

## Task 2: Ship completion and document manual setup

**Interfaces:**

Consume Task 1's shell definitions and completion helpers with their declared keyword arguments.
Consume the existing `PackageCheck#build(destination)` and `Gem::Package` extraction APIs.
Produce packaged paths `completions/jmespath.bash`, `completions/_jmespath`, and `docs/guides/completion.md`.
No public Ruby API changes are required.

- [x] **Step 1: Write failing artifact checks.**

Extend `spec/packaging/gem_spec.rb` to assert all three packaged paths.
Extract the built gem into the existing temporary test directory.
For R5, load each extracted definition and complete both executable names with CLI executables absent from PATH.
Retain access to shell binaries and standard Zsh completion facilities.
Assert a unique option and a path containing spaces complete through the shared helper.
Run `bundle exec rspec spec/packaging/gem_spec.rb`; expect missing-asset failures.

- [x] **Step 2: Package and document the feature.**

Add explicit completion asset patterns to `spec.files` in `jmespath-ruby.gemspec`.
Write the guide with an installed gem path discovered through RubyGems, preserving spaces through shell quoting.
Show session-local Bash sourcing and Zsh `fpath` setup before `compinit`.
Explain optional persistent setup as manual user actions; run no commands that edit user configuration.
Document both command names, both path options, equals values, spaces, the delimiter, and O1's conflict behavior.
Link the guide from README CLI documentation and `CLI::HELP`; update affected help assertions.

- [x] **Step 3: Verify the complete deliverable.**

Run `bundle exec rspec spec/integration/cli_completion_spec.rb spec/packaging/gem_spec.rb` and expect zero failures.
Run `env RUBOCOP_CACHE_ROOT=/private/tmp/jmespath-rubocop-cache bundle exec rake` and expect every gate to pass.
Run `bundle exec rake docs` and expect success.
Run the oss-writing prose checker on changed Markdown files and `git diff --check`; expect zero findings.
Manually try both documented shell setups against extracted assets in disposable shell sessions.
Verify filenames containing spaces become one argument, including equals-value syntax.
Record shell versions, skips, package evidence, and full-gate results in the plan.

- [x] **Step 4: Commit the packaged feature.**

Stage only task files and completed plan checkboxes.
Commit with `feat(cli): package shell completion`.
Report local verification; preserve separate authorization for remote operations.

## Execution evidence

Implemented on `feat/cli-completion` in `/Users/leonid/.codex/worktrees/4fd0/jmespath-ruby`.
The baseline passed 93 CLI examples.
Shell tests failed before assets existed; packaging and help checks failed before inclusion and documentation changes.
Independent QA found Bash equals-boundary errors, each covered by failing regressions before correction.
A separate regression caught option-name directories changing option insertion; filename mode now applies only to path arguments.
The final full gate passed 6663 examples with 100% line and branch coverage.
RuboCop, RBS, Steep, complexity analysis, and executable documentation checks passed.
`bundle exec rake docs` passed with 100% public documentation coverage.
Bash 3.2.57 and Zsh 5.9 passed syntax and real terminal tests; no installed-shell checks were skipped.
Other shell versions were not available for local verification.
Built gem checks verified both assets and the guide, then exercised extracted definitions without CLI executables on PATH.
Independent tmux QA verified exact manual setup, both names, both terminal widths, literal quoting, directories, and unreadable inputs.
Focused follow-ups passed 34 and seven scenarios; newline filenames also completed as one argument.
QA evidence: `/private/tmp/jmespath-completion-qa.SWhbb6/report.md`, `/private/tmp/jmespath-completion-qa-followup.nE0bCD/report.md`, and `/private/tmp/jmespath-completion-qa-collision.lJcNGa/report.md`.
Prose and whitespace checks passed.
The installed Ruby/YARD combination emitted its existing `irb/notifier` warning during documentation checks.
Independent code review found one important home-path defect and two minor groups.
The home-path regressions failed before correction and passed afterward; the full gate then passed 6663 examples.
A focused independent QA follow-up passed ten checks, including accepted arguments and the actual selected HOME or literal paths.
Its evidence is `/private/tmp/jmespath-completion-qa-home.hhn9f1/report.md`.

### F2 and F3 follow-up

F2: Both shells now normalize quoted option names, delimiters, and ANSI-C filename prefixes.
Zsh preserves quoted literal tildes in equals values and continues through their directories.
Whole-assignment quotes preserve option text, apostrophes, and literal home references.
Bash follows ANSI-C null termination and preserves invalid hexadecimal escapes without diagnostics.
F3: Bash now matches filename prefixes before the cursor and preserves native Readline insertion behavior.
Readline can repeat existing trailing text; the same input reproduces this with Bash's built-in filename completion.
The 22 focused regressions passed, including exact accepted arguments for open and closed ANSI-C quotes and repeated directory completion.
The follow-up full gate passed 6685 examples with 100% line and branch coverage.
Independent Bash review verified the full-assignment and ANSI-C edge cases.
Final terminal evidence is `/private/tmp/jmespath-followup/final-qa.json`.
Zsh retains native whole-word matching when `COMPLETE_IN_WORD` is unset; the cursor driver now uses explicit Emacs bindings.

### Review rulings

D1: Retain the approved exclusions for Fish, expression completion, and conflict filtering.
Cost: those features remain unavailable.
D2: Keep arbitrary shell substitution evaluation outside completion; safely expand only supported HOME references.
Cost: other constructed path prefixes may remain incomplete.
