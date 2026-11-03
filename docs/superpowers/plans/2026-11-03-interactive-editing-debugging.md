# Interactive editing and debugging implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add terminal editing, bounded history, function completion, and readable inspection commands to interactive query sessions.

**Architecture:** Keep document loading in `CLI` and query processing in `InteractiveSession`. Isolate Reline state and completion integration in a private editor adapter. Render public explanation and trace data through a private report formatter.

**Tech Stack:** Ruby 3.3+, Reline 0.7, JSON, RSpec, RBS, Steep, and standard-library PTY and Open3.

**Spec:** [Approved design](../specs/2026-11-03-interactive-editing-debugging-design.md).

## Global constraints

- Retain the most recent 500 submitted queries in memory, in submission order.
- Start each session with empty history and discard its history on exit.
- Create no history files and modify no shell configuration.
- `:trace` compiles once and calls `Expression#trace` once with `limit: 1000`.
- Never run an additional ordinary search to obtain the traced result.
- Route editor display and prompts to the injected diagnostic stream, never stdout.
- Piped input receives no prompts.
- Retain caller ownership of all injected streams.
- EOF and `:quit` return status 0 after recoverable failures.
- Startup failures retain status 1; invalid CLI arguments retain status 2.
- Preserve Ruby 3.3+, both executable names, ordinary search, all noninteractive modes, and imported fixtures.
- Exclude persistent history, multiline queries, reloads, field completion, custom registries, and shell completion changes.
- Read both this plan and the spec before execution. Ask which checkout or worktree to use before implementation.

## Review focus

- R1: Redirected stdout must remain JSON-only while terminal stdin and stderr retain editing.
- R2: A prior Reline consumer's history, callbacks, and streams must survive successful and failed sessions.
- R3: Completion in the middle of a token must replace its suffix without changing adjacent Unicode or quoted text.
- R4: Bracketed paste containing multiple physical lines must retain one-query-per-line behavior without enabling multiline editing.
- R5: Trace serialization or diagnostic failures must not emit a misleading successful result or retry failed writes.

## Deliveries and file map

Tasks 1 and 2 form delivery D1, editing and history. Task 3 forms D2, completion. Tasks 4 and 5 form D3, inspection.
Task 6 checks the combined result. Each delivery includes its own documentation and full quality checks before integration.
No push, PR, merge, or publication is authorized by this plan.

| File | Responsibility |
| --- | --- |
| `jmespath-ruby.gemspec`, `Gemfile.lock` | Declare and resolve Reline |
| `lib/jmespath/cli/interactive_editor.rb` | Terminal qualification, reads, editor history, Reline state, and cleanup |
| `lib/jmespath/cli/interactive_completion.rb` | Pure cursor-aware candidate and replacement calculation |
| `lib/jmespath/cli/inspection_report.rb` | Readable explanations and trace reports |
| `lib/jmespath/cli/interactive_session.rb` | Reader selection, query submission, history policy, and command dispatch |
| `lib/jmespath/cli.rb` | Require private helpers without initializing Reline |
| `lib/jmespath/cli/help.rb` | Interactive topic help |
| `sig/internal/cli.rbs` | Session declarations and narrow stream protocols |
| `sig/internal/cli_interactive_editor.rbs` | Editor and completion declarations |
| `sig/internal/cli_inspection_report.rbs` | Report declarations using public inspection shapes |
| `spec/unit/cli_interactive_editor_spec.rb` | Qualification, state restoration, cancellation, and history |
| `spec/unit/cli_interactive_completion_spec.rb` | Token boundaries, quotes, cursor offsets, and deterministic completion |
| `spec/unit/cli_inspection_report_spec.rb` | Report structure, escaping, locations, and truncation |
| `spec/unit/cli_interactive_session_spec.rb` | Submission, commands, routing, and recovery |
| `spec/integration/cli_interactive_spec.rb` | Startup, compatibility, and pipe regressions |
| `spec/integration/cli_interactive_terminal_spec.rb` | Both executables through a pseudo terminal |
| `spec/packaging/gem_spec.rb` | Dependency declaration and packaged helpers |
| `.github/workflows/ci.yml` | Linux matrix and macOS terminal checks |
| `README.md`, `docs/guides/command-line.md`, `docs/guides/compilation.md` | Feature documentation and API links |

## Dependency and adapter boundary

[Upstream Reline v0.7.0](https://github.com/ruby/reline/tree/v0.7.0) supports Ruby 2.6+ and declares `io-console ~> 0.5`.
Use `spec.add_dependency "reline", "~> 0.7.0"`; resolve through the project's Bundler workflow during Task 1.
Recheck upstream before adoption if execution occurs after another release.

Use `Reline.readline("jmespath> ", false)` and manual history insertion.
Readline configuration comes from Reline; the application writes no configuration or history files.
Use `Reline.input=`, `Reline.output=`, completion properties, and `Reline::HISTORY` within the adapter only.
Reline exposes `line_buffer`, byte-based `point`, `delete_text`, and `insert_text`, but marks several accessors undocumented.
Restoring input also requires checking source-exposed state because the module provides no matching public input getter.
The user approved a narrow exception for exported adapter calls and one private read of the backend's `@input`.
Verify each against the selected release and cover it directly; restore input through its setter and never patch Reline classes.
If the required restoration or cursor behavior cannot be achieved through exported methods, stop and report the evidence before implementation continues.

### Task 1: Connect terminal editing and cleanup

**Files:** Create `interactive_editor.rb`, its unit spec, its RBS file, and the terminal integration spec. Modify session, CLI requires, gemspec, lockfile, and packaging tests.

**Interfaces:** `InteractiveEditor.supported?(input:, errors:) -> bool`; `.new(input:, errors:)`; `#open { ... } -> block result`; `#gets -> String?`; `#remember(query) -> void`.
`#gets` retries after edit cancellation and returns nil for EOF. IO exceptions propagate to session failure handling.
The plain session reader remains `input.gets`; editor prompts belong exclusively to the adapter.

- [ ] **Step 1: Add qualification and loading regressions.**

Assert `supported?` is false for gets-only objects, StringIO reporting `tty? == true`, nonterminal input, nonterminal errors, and unsupported terminals.
Require actual open terminal IO objects and the methods needed by the selected Reline backend.
Use fresh Ruby subprocesses to assert Reline is absent from `$LOADED_FEATURES` after ordinary searches, noninteractive CLI calls, and pipe sessions.
Assert loading the CLI helpers alone does not initialize Reline.

- [ ] **Step 2: Add terminal and cleanup regressions.**

For each executable, launch stdin and stderr on a PTY with stdout on a separate pipe, using `TERM=xterm-256color`.
Handle bounded cursor-position requests from Reline in the PTY harness; wait for prompts rather than sleeping.
Type `nme`, move left twice, insert `a`, and submit against `{"name":"café"}`; assert stdout is exactly `"café"\n`.
For R1, assert prompts and redraw sequences appear only on the PTY, with valid JSON-only stdout.
Cancel partial input with Ctrl-C, then submit `name`; assert exactly one result and a usable prompt.
Test EOF, `:quit`, stream failures, and unexpected exceptions; compare terminal attributes before and after each session.
For R2, preseed Reline streams, callbacks, configuration, and history; assert their restoration after normal exit, cancellation, and exceptions.
Verify document-file closure precedes editor initialization and caller-owned streams remain open.

- [ ] **Step 3: Run the new regressions before implementation.**

Run `bundle exec rspec spec/unit/cli_interactive_editor_spec.rb spec/integration/cli_interactive_terminal_spec.rb`.
Expect feature failures caused by the absent adapter, not invalid fixture setup.

- [ ] **Step 4: Implement and connect the adapter.**

Add the approved dependency and resolve with `bundle install` without unrelated upgrades.
Snapshot every changed exported property inside `#open`; restore it in `ensure` on every exit.
Bind the actual input and errors streams before reading; preserve stdout independently.
Rescue `Interrupt` only around terminal reads, discard the interrupted edit, and retry the prompt.
Keep the ordinary reader path free of editor initialization and new terminal requirements.
Declare narrow RBS interfaces; do not weaken the public injected-stream protocols.

- [ ] **Step 5: Verify and commit connected editing.**

Run the Task 1 command plus `bundle exec rspec spec/unit/cli_interactive_session_spec.rb spec/integration/cli_interactive_spec.rb spec/packaging/gem_spec.rb`.
Require zero failures and inspect the dependency diff for unrelated changes.
Commit scoped files with `feat(cli): add terminal query editing`.

### Task 2: Add bounded history and finish delivery D1

**Files:** Modify editor, session, their unit specs, terminal spec, help, command-line guide, and RBS declarations.

**Interfaces:** Session submission calls `editor.remember(expression)` only for valid UTF-8, nonblank query lines, before evaluation.
`InteractiveEditor::HISTORY_LIMIT = 500`; `#remember` retains duplicate queries and evicts the oldest entry.

- [ ] **Step 1: Add history and physical-line regressions.**

Use an editor double to assert that `name`, invalid query `items[`, and a repeated `name` are recorded in that order.
Assert blanks, malformed UTF-8, `:help`, `:quit`, and unknown colon commands are excluded.
Insert queries `q0` through `q500`; assert 500 entries remain, first `q1`, last `q500`.
Assert query whitespace survives line-ending removal and CRLF and final unterminated lines retain their prior behavior.
Use PTY up-arrow recall to correct an invalid query and evaluate it against the same loaded document.
Run two sessions in one process and verify empty initial session history plus restored external history.
Guard history-file writes and compare an isolated HOME directory before and after the child session.
For R4, paste `name\nflag` as bracketed paste; assert two physical submissions produce two JSON results and no multiline query.

- [ ] **Step 2: Confirm failures.**

Run `bundle exec rspec spec/unit/cli_interactive_editor_spec.rb spec/unit/cli_interactive_session_spec.rb spec/integration/cli_interactive_terminal_spec.rb`.
Expect the history and paste assertions to fail for the missing behavior.

- [ ] **Step 3: Implement history and document editing.**

Disable automatic history insertion and enforce policy at the session submission boundary.
Set the session history limit independently of user Reline history settings, restoring those settings on exit.
Preserve one physical query per line when pasted input includes newlines; queue complete lines without evaluating partial edits.
Document editing, Ctrl-C, the 500-entry session lifetime, and the plain-reader fallback in session and topic help.
Add no persistent file path or shell setup instructions.

- [ ] **Step 4: Verify delivery D1 and commit.**

Run the Task 2 command, `env RUBOCOP_CACHE_ROOT=/private/tmp/jmespath-rubocop-cache bundle exec rake`, and `bundle exec rake docs`.
Require zero failures and the repository's 100% line and branch coverage gates.
Commit scoped files with `feat(cli): retain bounded session query history`.

### Task 3: Add function completion and finish delivery D2

**Files:** Create completion helper and spec; modify editor, its RBS file, terminal spec, session help, topic help, and command-line guide.

**Interfaces:** `InteractiveCompletion.new(functions: Functions.default)`; `#complete(line, point:) -> Hash` with keys `:line`, `:point`, and `:candidates`.
Points are byte offsets at valid UTF-8 boundaries; candidates are sorted function-name strings.
The editor applies returned buffer changes and displays alternatives only when no common-prefix extension is possible.

- [ ] **Step 1: Add pure completion regressions.**

Assert `leng` becomes `length`, with no appended parentheses or whitespace.
Assert ambiguous `to_` returns sorted names without changing text; assert `to` extends to their common prefix.
Assert unknown `zzzz` and an empty prefix leave text unchanged with empty candidates.
Use `"[\"é\", lengzz(@)]"` with the cursor after `leng`; assert only `lengzz` becomes `length`.
Assert unchanged completion inside quoted identifiers, single-quoted strings, and backtick literals, including escaped delimiters and backslashes.
Cover cursor positions immediately after closing literals and adjacent to operators, parentheses, token starts, and token ends.
Suppress command-name completion; allow query completion within the arguments of `:explain` and `:trace` once those commands exist.
For R3, assert exact surrounding bytes and returned byte offset with Unicode before and after the token.
Use registry spies to assert public names are consulted; guard compilation, search, trace, callbacks, and document access against calls.

- [ ] **Step 2: Confirm failures.**

Run `bundle exec rspec spec/unit/cli_interactive_completion_spec.rb`.
Expect failures for the absent completion class.

- [ ] **Step 3: Implement the helper and editor callback.**

Scan quote state from the beginning of the line to the cursor, respecting the query language's escape rules.
Find ASCII token bounds around the byte cursor and replace the entire token from its start through its suffix.
Use lexical candidates and their longest common prefix; preserve all other bytes.
Configure Reline's word and quote boundaries inside the adapter so its built-in completion cannot change the helper's replacement scope.
Cover the real callback behavior through PTY tests, including mid-token deletion and ambiguity display on stderr.
Restore completion settings and callbacks on exit, including callback failures.

- [ ] **Step 4: Verify delivery D2 and commit.**

Run the completion spec, editor spec, and terminal spec, then the full quality and documentation commands from Task 2.
Document names-only completion, quote suppression, ambiguity, no-match behavior, and terminal availability.
Commit scoped files with `feat(cli): complete interactive function names`.

### Task 4: Add functions and explanation commands

**Files:** Create report helper, report spec, and report RBS file; modify session, CLI requires, session spec, help, and command-line guide.

**Interfaces:** `InspectionReport.explain(explanation) -> String`, consuming the public `Expression#explain` hash.
Session command dispatch recognizes exact command names and preserves the query remainder after separating horizontal whitespace.
Continue using `FunctionListing.render(Functions.default) -> String` and `FailureDiagnostic.format(error, expression)`.

- [ ] **Step 1: Add dispatch and report regressions.**

Assert `:functions` writes names, signatures, descriptions, and the established legend to stderr, with empty stdout.
Assert `:explain user.name` writes an indented tree with IDs, operation names, child roles, details, and source locations.
Use public explanation fixtures with nil ranges, nested literal data, Unicode, and control characters to verify location handling and escaped output.
Assert an unknown function can be explained without resolution; guard search, trace, and document access against calls.
Assert exact boundaries reject `:explainx`; missing queries and surplus arguments to argument-free commands recover before a valid query.
Assert separating whitespace is excluded from source coordinates while the complete remaining query retains trailing whitespace.
Retain escaped unknown-command diagnostics, malformed UTF-8 recovery, and all original query cases.

- [ ] **Step 2: Confirm failures.**

Run `bundle exec rspec spec/unit/cli_inspection_report_spec.rb spec/unit/cli_interactive_session_spec.rb`.
Expect missing report and command failures.

- [ ] **Step 3: Implement commands and explanation rendering.**

Compile explanations once without evaluating them; traverse public nodes in their provided child order.
Compute one-based character columns from public byte offsets; explicitly label unavailable source locations.
Escape dynamic text and control characters before terminal rendering.
Keep result and diagnostic writes inside their established error boundaries and flush stderr when supported.
Update command help and guide examples for only these implemented commands.

- [ ] **Step 4: Verify and commit.**

Run the Task 4 command plus interactive integration and completion specs; require zero failures.
Commit scoped files with `feat(cli): inspect functions and query structure in sessions`.

### Task 5: Add tracing and finish delivery D3

**Files:** Modify report helper and RBS, session and RBS, report and session specs, both integration specs, help, README, command-line guide, and compilation guide.

**Interfaces:** `InspectionReport.trace(explanation, report, limit:) -> String`, consuming public explanation and trace hashes.
Session trace handling compiles once, obtains `compiled.trace(data, limit: 1000)`, and uses that compiled expression's explanation for locations.

- [ ] **Step 1: Add trace and failure regressions.**

For `items[*].name` over `{"items":[{"name":"Ada"},{},{"name":false}]}`, assert stdout is exactly `["Ada",false]\n`.
Assert ordered `field_null` and `projection_omission` events include IDs, locations, public reasons, and zero-based item context.
Cover filter exclusions, nested contexts, scalar null and false results, and a no-events trace.
Create more than 1,000 events; assert only 1,000 are rendered, a truncation notice appears, and the full result still matches ordinary search.
Use spies to assert one compile and one trace call, with no search call for the traced command.
For R5, force JSON serialization failure before any report write; assert no result and recovery before a valid query.
Fail a report write or flush; assert status 1, no result for that trace, no subsequent input read, and no repeated failed write.
Fail result output after a successful report; assert status 1 and terminal cleanup.
Test missing arguments, syntax, type, arity, and unknown-function failures followed by a successful ordinary query.

- [ ] **Step 2: Confirm failures.**

Run `bundle exec rspec spec/unit/cli_inspection_report_spec.rb spec/unit/cli_interactive_session_spec.rb`.
Expect failures for the absent trace command and renderer.

- [ ] **Step 3: Implement tracing and finish command documentation.**

Serialize `report[:value]` before emitting diagnostic reports or JSON results.
Render only public event data and explanation locations, preserving event order and public identifiers.
State that evaluation completed when events are truncated; do not invent the total number of discarded events.
Write the report to stderr before the single compact JSON result and preserve result flushing.
Extend both executable integration tests with all commands in piped and terminal sessions.
Document routing, one evaluation, limits, recovery, and the structured Ruby alternatives.
Update the compilation guide's statement about CLI tracing to describe the session command accurately.

- [ ] **Step 4: Verify delivery D3 and commit.**

Run report, session, completion, editor, and both interactive integration specs, then the full quality and documentation commands from Task 2.
Commit scoped files with `feat(cli): trace interactive query results`.

### Task 6: Verify combined platform and packaging behavior

**Files:** Modify `.github/workflows/ci.yml`, terminal integration specs, packaging tests, and platform documentation only when required.

**Interfaces:** Both executables retain the same CLI arguments and exit statuses. This task introduces no product interfaces.

- [ ] **Step 1: Cover platform and packaged execution.**

Run terminal integration specs on the Linux Ruby 3.3, 3.4, and 4.0 matrix and the macOS job.
Add the terminal spec explicitly to macOS checks because its job otherwise runs only packaging and shell completion.
Verify packaged helpers and the Reline dependency through the repository's isolated packaging workflow.
Use packaged executable tests when the existing harness supports them; do not install globally.
Use bounded timeouts, close descriptors, and terminate and reap children after failed PTY tests.
Document verified platform boundaries without claiming Windows support from Linux or macOS evidence.

- [ ] **Step 2: Run final checks.**

Run `env RUBOCOP_CACHE_ROOT=/private/tmp/jmespath-rubocop-cache bundle exec rake` and `bundle exec rake docs`.
Require zero failures, 100% line and branch coverage, and passing RBS, Steep, CRAP, and documentation gates.
Run `bundle exec rake audit` separately and report any advisories independently of test results.
Run the oss-writing prose checker on changed documentation and `git diff --check`.
Review the complete diff against the spec and inspect every unrelated change before staging.
Report local, PTY, packaging, and CI evidence separately; CI is unverified until a remote run actually passes.

- [ ] **Step 3: Commit verification changes when present.**

Use `ci(cli): verify interactive editing across platforms` for workflow changes and their focused tests.
If no changes remain, record verification evidence without an empty commit.

## Execution handoff

This plan is proposed for review and does not start implementation.
Review includes the narrow, version-tested Reline accessor exception described above.
Prefer native execution because editing, history, and completion share adapter state and need sequential integration.
Choose the checkout or worktree before executing Task 1.
