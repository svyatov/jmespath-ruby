# Developer discoverability implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Ruby tasks easy to find and provide concise default help with complete CLI topic references.

**Architecture:** Keep one command-line guide and five offline help topics. Dispatch help after literal validation and before execution parsing. Extend the packaged shell definitions without invoking executables.

**Tech Stack:** Ruby 3.3+, RSpec, RBS, YARD, Bash 3.2-compatible completion, and Zsh completion. Add no dependencies.

**Spec:** [Approved design](../specs/2026-11-03-developer-discoverability-design.md).

## Global constraints

- Serve Ruby library users first while keeping shell tasks directly accessible.
- Preserve the documented replacement contract for jmespath.rb and every query execution contract.
- Exclude query methods, language changes, execution changes, dependencies, editor integrations, and browser tools.
- Keep benchmark methodology and recorded measurements unchanged.
- Interactive enhancements from issue #53 remain separate.
- Preserve the exact two-argument literal-validation check before help dispatch.
- Topic names are case-sensitive; abbreviations, equals forms, unknown topics, and surplus arguments are usage failures.
- Valid default and topic help write only to stdout and return status 0.
- Help requests, including invalid requests, never open document or query files or read stdin.
- No pull request, push, merge, or release is authorized by approval of this design alone.

The user selected the current checkout and a branch. Continue on `docs/developer-discoverability-design`; preserve unrelated changes.
This plan adds documentation and tests before changing behavior. Execute tasks sequentially.

## Review focus

- R1: Help-like filenames and quoted query literals must retain execution behavior, without triggering help dispatch. Task 2 pins this.
- R2: `--validate -h` and `--validate --help` must retain exact literal-query diagnostics. Task 2 pins this.
- R3: A closed output stream during help must return status 1 without input access. Task 2 pins this.
- R4: Completion after a topic or inside literal validation must not suggest topic arguments. Task 3 pins this.
- R5: README fragment links must reach real headings; file-only link checks cannot detect broken anchors. Task 1 checks this.

## File responsibilities

| File | Responsibility |
| --- | --- |
| `README.md` | Ruby-first task examples, migration warnings, and guide navigation |
| `docs/guides/command-line.md` | Complete CLI reference with stable topic sections |
| `docs/guides/comparison.md` | Destination for any unique benchmark material removed from the README |
| `.yardopts` | Include command-line, comparison, and completion guides in generated documentation |
| `lib/jmespath/cli/help.rb` | Usage, concise default help, and five topic texts |
| `lib/jmespath/cli.rb` | Help dispatch and usage guidance; preserve query execution |
| `sig/internal/cli.rbs` | Types for private help rendering and dispatch |
| `spec/integration/cli_help_spec.rb` | Help behavior and no-input regression tests |
| `spec/integration/cli_*spec.rb` | Relocated prose assertions and revised usage guidance expectations |
| `completions/jmespath.bash`, `completions/_jmespath` | Topic completion without changing path handling |
| `spec/integration/cli_completion_spec.rb` | Both shells, executable names, aliases, and argument positions |
| `spec/packaging/gem_spec.rb` | Guide packaging and topic completion from extracted assets |

Keep `arguments.rb`, `argument_parser.rb`, evaluation code, public signatures, and in-session `:help` unchanged unless a demonstrated requirement forces a smaller change.

## Contract destination inventory

All guide destinations below refer to `docs/guides/command-line.md`, except explicit alternate paths.
Compare this inventory against the source README and `lib/jmespath/cli/help.rb` before deleting prose.

| Contract to preserve | Guide destination | Topic destination |
| --- | --- | --- |
| Both executable names, stdin default, `--file`, positional query, `--query-file`, exactly one query source | Quick start; Input | input |
| UTF-8 documents; document file closed after parsing and before single-document evaluation | Input | input |
| Query UTF-8 without trimming or newline conversion; empty queries fail; Unicode coordinates retained | Input | input |
| Query files read and closed before documents; missing queries leave document input untouched | Input | input |
| Single-document JSON parsing precedes query compilation | Input | input |
| Literal `-` paths for both sources; spaces; option-like names using equals values or `./` | Input | input |
| Exact option names; options before or after expressions; `--` delimiter | Input | input |
| Missing values, unknown/repeated options, conflicting/absent query sources fail before input access | Input; Exit statuses | input |
| Help/version/function listing input independence; standalone restrictions and topic exception | Help; Functions; Exit statuses | all applicable topics |
| Compact and pretty JSON for all result types, Unicode, two-space indentation, final newline | Output | output |
| Raw strings retain embedded/trailing newlines and receive another newline; nonstrings remain JSON | Output | output |
| Repeated or conflicting output flags, validation conflicts, diagnostics and statuses retained | Output | output |
| JSON Lines compiles once before document access; one JSON value per physical line | Output, JSON Lines subsection | output |
| JSON Lines rejects blank/whitespace lines; accepts LF, CRLF, final lines without LF; valid empty input succeeds | Output, JSON Lines subsection | output |
| JSON Lines emits compact results including null/false; stops on failure and preserves earlier output | Output, JSON Lines subsection | output |
| `Input line N:` failures; compilation/file-open errors have no line prefix | Output, JSON Lines subsection | output |
| JSON Lines memory follows record/result plus compiled query; normal buffering; owned files close | Output, JSON Lines subsection | output |
| CLI-injected stream requirements: document `read`, line modes `gets`, output `puts`; caller streams remain open | Input; Interactive | input, output, interactive |
| Syntax/type/arity locations and carets; unknown-function suggestions; JSON errors omit document fragments | Exit statuses; `errors.md#cli-diagnostics` | input, validate, functions |
| Function arguments and expression-reference results validated; runtime failures return 1 | Functions; `functions.md` | functions |
| Alphabetical listing from metadata, descriptions, notation legend, narrower runtime checks, standalone restrictions | Functions; `functions.md#command-line-reference` | functions |
| Function listing status 0, output failure 1, usage failure 2 with empty stdout | Functions; Exit statuses | functions |
| Interactive requires document file, rejects query sources, other modes, information flags, and repeats | Interactive | interactive |
| Document loaded once and closed before prompt/read; one UTF-8 query per line; LF/CRLF/final line accepted | Interactive | interactive |
| Ignore empty/space/tab lines; `:help`, `:quit`, EOF; successful JSON newline and optional flush | Interactive | interactive |
| Terminal-only prompts; results stdout; help/prompts/diagnostics stderr; pipes have no prompts | Interactive | interactive |
| Recover from query failures, unknown commands, invalid UTF-8; no result for failed query | Interactive | interactive |
| EOF/quit status 0 after query errors; document/stream failures 1; usage failures 2 | Interactive; Exit statuses | interactive |
| Optional input `tty?`, output `flush`; terminal diagnostic stream needs `print` and `flush` | Interactive | interactive |
| No history, completion, multiline editing, document reload; caller streams remain open | Interactive | interactive |
| Syntax-only validation leaves stdin untouched; unknown functions valid; document files unavailable | Validation | validate |
| Query-file validation with either option order; exact two-argument validation treats flags as query text | Validation | validate |
| Validation success silent 0; query failure stderr 1; usage failure empty stdout and stderr guidance 2 | Validation; Exit statuses | validate |
| Ruby validation API `JMESPath.validate(expression, max_depth: 128)` | Validation; `errors.md` | validate |
| Manual Bash/Zsh setup for both executables | `completion.md`, linked from guide | default-help pointer |

Task 1 retains standalone-help wording. Task 2 revises that wording to permit exactly one topic.
Keep full function notation in `functions.md` and the `functions` topic; do not repeat it in default help.

## Task 1: Publish task-oriented documentation locally

**Files:** Modify `README.md`, `.yardopts`, `spec/packaging/gem_spec.rb`; create `docs/guides/command-line.md`; modify `docs/guides/comparison.md` only for unique relocated facts.

**Interfaces:** Consumes the present CLI and public Ruby interfaces. Produces `command-line.md` anchors `quick-start`, `input`, `output`, `validation`, `functions`, `interactive`, `help`, and `exit-statuses`.

- [ ] **Step 1:** Add a packaging assertion that the artifact includes `docs/guides/command-line.md`.
- [ ] **Step 2:** Run `bundle exec rspec spec/packaging/gem_spec.rb`. Confirm the missing guide causes the assertion to fail.
- [ ] **Step 3:** Write the guide from the inventory, retaining all rules and using only implemented commands.
- [ ] **Step 4:** Reorder the README per the design, preserving installation and migration instructions, six task links, and concise examples.
- [ ] **Step 5:** Move unique benchmark detail into the comparison guide and keep performance links after practical examples.
- [ ] **Step 6:** Include command-line, comparison, and completion guides in `.yardopts` and README navigation.
- [ ] **Step 7:** Run `bundle exec rake docs:check`, `bundle exec rake docs`, and the packaging specification. Expect success and generated guide pages.
- [ ] **Step 8:** Check local links and fragments with a temporary standard-library Ruby script. Verify each inventoried rule at its destination.
- [ ] **Step 9:** Use a temporary Ruby `Open3` runner to execute every shell example against small fixtures with both executables.

Use `document.json` containing `{"user":{"name":"Ada"},"items":[1,2]}`, `query.jmespath` containing `user.name`, and JSON Lines with Ada and Lin records.
Assert compact name output `"Ada"\n`, raw output `Ada\n`, pretty arrays with two-space indentation, and two JSON Lines results.
Assert validation emits nothing with status 0, function listing includes `length(string|array|object)`, and a piped interactive query exits 0.
Create literal filenames `-`, `--document.json`, and `my document.json` for the corresponding examples.
Check failure examples for their documented status and stream routing. Do not install the gem or any dependencies.

- [ ] **Step 10:** Run the full quality gate defined below, then commit only Task 1 files as `docs: organize developer tasks and CLI reference`.

## Task 2: Add default and topic help

**Files:** Modify `lib/jmespath/cli/help.rb`, `lib/jmespath/cli.rb`, `sig/internal/cli.rbs`, `docs/guides/command-line.md`, and affected CLI specifications; create `spec/integration/cli_help_spec.rb`.

**Interfaces:** Add private positional methods `JMESPath::CLI::Help.render(topic)` and `JMESPath::CLI.help(argv, output)`.
Their RBS declarations are `def self.render: (String?) -> String` and `def self.help: (Array[String], _Writer) -> Integer`.
Keep `CLI::USAGE` for execution forms and `CLI::HELP` for default text. Add `Help::TOPICS: Hash[String, String]` for topic text.
Unknown topics raise `OptionParser::InvalidArgument`; excessive arguments fail before rendering.

- [ ] **Step 1:** Add tests named `renders every topic without accessing input`, `rejects malformed help before input access`, and `preserves literal validation before help`.

For both `--help` and `-h`, exercise no topic and each of `input output validate functions interactive`.
Assert status 0, nonempty stdout, empty stderr, frozen argv unchanged, no `File.open`, and no input `read`, `gets`, or `tty?`.
Assert default output contains all 11 public option names and each `jmespath --help TOPIC` command, with no full notation legend.
Assert topic output contains examples, restrictions, streams, applicable statuses, and the guide path and repository URL.
For malformed requests, assert status 2, empty stdout, and stderr containing `Usage:` and `jmespath --help`.
Include unknown/empty/uppercase/abbreviated topics, `--help=input`, `-hinput`, repeated help, surplus topics, mode flags, and file flags in both orders.
Retain non-help version/function-listing restrictions and unsupported combinations.

```ruby
expect(run_cli(%w[--validate --help])).to eq(
  [1, "", "Expected a digit at line 1, column 1\n--help\n^\n"]
)
```

Compare `--validate -h` against `JMESPath.validate("-h")` formatted through `JMESPath::Diagnostic.format`.
Add R1 execution tests for a file named `--help`, selected with `--file=--help`, and query text `'--help'`.
Add R3 tests with a closed `StringIO` output and an output writer raising `Errno::EPIPE`; expect status 1 without input access.
Run each default/topic invocation through both executables with `Open3.capture3`; compare complete stdout, stderr, and statuses.

- [ ] **Step 2:** Run `bundle exec rspec spec/integration/cli_help_spec.rb`; confirm topic requests fail under the preceding implementation.
- [ ] **Step 3:** Implement the two private interfaces and their RBS declarations. Keep literal validation first, then exact initial help dispatch, then other information modes and execution.
- [ ] **Step 4:** Replace the long `HELP` body with usage, all public options, common examples, topic commands, and completion/guide pointers.
- [ ] **Step 5:** Write the five complete topic texts using the inventory. Reuse `FunctionListing::LEGEND` in function help without changing listing output.
- [ ] **Step 6:** Append `Use jmespath --help for options and topic help.` to usage errors. Preserve execution usage forms and update independent expected usage strings.
- [ ] **Step 7:** Move detailed help assertions to their topic in `cli_spec.rb`, `cli_functions_spec.rb`, `cli_interactive_spec.rb`, `cli_pretty_spec.rb`, and `cli_raw_output_spec.rb`.

Retain behavior assertions attached to those tests. Keep `cli_file_spec.rb` unknown-topic cases such as `[flag, "@"]` invalid.
Update the guide's help restrictions and document the topic syntax and alias. Add a short help pointer to the README CLI example if useful.

- [ ] **Step 8:** Run `bundle exec rspec spec/integration/cli_help_spec.rb spec/integration/cli_spec.rb spec/integration/cli_file_spec.rb spec/integration/cli_query_file_spec.rb spec/integration/cli_functions_spec.rb spec/integration/cli_pretty_spec.rb spec/integration/cli_raw_output_spec.rb spec/integration/cli_json_lines_spec.rb spec/integration/cli_interactive_spec.rb`.
- [ ] **Step 9:** Run the full quality gate and documentation build. Confirm 100% line/branch coverage, CRAP limits, and type checks without suppressions.
- [ ] **Step 10:** Commit only Task 2 files as `feat(cli): add topic help`.

## Task 3: Complete help topics in Bash and Zsh

**Files:** Modify `completions/jmespath.bash`, `completions/_jmespath`, `spec/integration/cli_completion_spec.rb`, `spec/packaging/gem_spec.rb`, and `docs/guides/completion.md`.

**Interfaces:** Consume Task 2's five exact topic names. Preserve `ShellCompletion.complete(**)` and `ShellCompletion.candidates(**)` and the shell registration for both executables.

- [ ] **Step 1:** Add `offers help topics only after initial help` tests for both shells, both executables, and both aliases.

```ruby
expect(ShellCompletion.candidates(shell: shell, root: root, line: "#{command} --help ").sort)
  .to eq(%w[functions input interactive output validate])
expect(complete(line: "#{command} -h val")).to eq("#{command} -h validate ")
```

For R4, assert no candidates after `--help input `, `--help input --`, `--validate --help `, and `-- --help `.
Also check `--help unknown ` and `@ --help ` do not offer topics.
Check quoted help/topic words and preserve filenames beginning with help-like text in file-value positions.
Extend the executable sentinel test to topic completion, proving the shell never invokes either executable.
In extracted-gem tests, assert topic completion works with CLI executables absent from `PATH`.

- [ ] **Step 2:** Run `bundle exec rspec spec/integration/cli_completion_spec.rb spec/packaging/gem_spec.rb`. Confirm topic assertions fail.
- [ ] **Step 3:** After decoding shell words, detect initial help and complete only its first topic argument. Keep path detection and literal validation separate.
- [ ] **Step 4:** Document topic completion in `completion.md`, retaining manual installation and quoting instructions.
- [ ] **Step 5:** Run `bundle exec rspec spec/integration/cli_completion_spec.rb spec/integration/cli_completion_quoting_spec.rb spec/packaging/gem_spec.rb`.
- [ ] **Step 6:** Run the full quality gate and documentation build, then commit only Task 3 files as `feat(cli): complete help topics in supported shells`.

## Final verification and handoff

- [ ] Run `env RUBOCOP_CACHE_ROOT=/private/tmp/jmespath-rubocop-cache bundle exec rake` after each task's final edits; expect exit 0.
- [ ] Run `bundle exec rake docs`; expect exit 0 and generated pages for every linked guide.
- [ ] Run `bundle exec rake audit` separately and report its result independently; do not change dependencies to repair unrelated advisories.
- [ ] Repeat the shell examples against final help behavior, and check every inventory destination and local fragment link.
- [ ] Delete temporary Ruby scripts and fixtures. Review the final diff and obtain the required code review through the selected execution workflow.
- [ ] Report committed changes, local verification, and limitations. Keep remote publication and CI claims separate from local evidence.

No additional test run is needed when the final gate already covers the unchanged final tree.
The first delivery contains Task 1; the second contains Tasks 2 and 3. Remote delivery requires separate authorization.
