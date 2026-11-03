# Interactive query editing and debugging

Status: approved by the user on 2026-11-03.
Scope: [issue #53](https://github.com/svyatov/jmespath-ruby/issues/53).

## Intent and boundaries

Make repeated query development practical against one loaded document.
Provide terminal editing, session history, function completion, and inspection commands through the interactive session.
Preserve the invocation, ordinary query behavior, injected streams, and documented jmespath.rb replacement contract.

Exclude persistent history, multiline queries, document reloads, field completion, custom registries, full-screen interfaces, and browser tools.
Do not change parser or evaluator interfaces, ordinary search initialization, shell completion, or unrelated CLI modes.
Terminal output entering stdout, history leaking between sessions, and extra query evaluations are design failures.

This is a CLI project with three independently usable deliveries.
The dependency choice and readable reports are user decisions.
Other concrete defaults below are proposed builder decisions, subject to approval of this document.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| O1: Declare Reline as a runtime dependency | Installs the editor with the gem | Adds Reline and its transitive dependencies | Selected by the user |
| O2: Load Reline only when independently available | Preserves the dependency list | Editing depends on the surrounding bundle | Rejected |
| O3: Readable inspection reports | Supports debugging within the terminal | Requires private text renderers | Selected by the user |
| O4: JSON inspection reports | Directly represents public API data | Nested data is harder to inspect beside prompts and diagnostics | Rejected |

Use Reline's documented interface and require it only after selecting a terminal editing session.
Retain a plain reader for streams and terminals that cannot support editing.
Dependency declaration guarantees installation, not terminal capability.
The implementation plan must verify a compatible release against upstream before choosing constraints and updating the lockfile.
The user has authorized dependency adoption; this design does not install anything.

## Session structure and terminal selection

Keep document loading and argument validation in `CLI`.
Load the document once and close its file before initializing the editor or accepting commands.
Keep command dispatch, history policy, evaluation, and result routing in the private session layer.
Use a private editor adapter for Reline integration and terminal cleanup.
Use private completion and report helpers without exposing parser or evaluator internals.

Select editing only when input and diagnostic output are actual usable terminal IO streams.
Check capabilities required by the supported Reline interface before initialization; `tty?` alone is insufficient.
Route editor display and prompts to the injected diagnostic stream, never stdout.
Redirected stdout does not prevent editing when the other streams qualify.
Unsupported terminals, nonterminal diagnostics, pipes, and injected readers use `gets` without requiring Reline.
The plain reader retains terminal prompts when input reports `tty?`, including the established prompt-stream requirements.
Piped input receives no prompts.

Snapshot any Reline state that the adapter changes, including streams, callbacks, history, and relevant configuration.
Restore it on EOF, `:quit`, interruption, and failure without closing caller-owned streams.
Sessions in the same process have isolated history and callbacks.
Concurrent terminal sessions within one process are outside the CLI contract; ordinary library calls remain independent.
Initialization and runtime IO failures terminate with status 1 after cleanup; they do not silently restart through another reader.
Unrelated programming exceptions propagate after cleanup.

## Editing and history

Support single-line cursor movement, insertion, deletion, and query recall through Reline.
Ctrl-C discards the current edit and presents another prompt without evaluating or recording partial input.
EOF and `:quit` terminate successfully.
Document this cancellation behavior for terminal editing; preserve the plain reader's interruption behavior.

Retain the most recent 500 submitted queries in memory, in submission order.
Record valid UTF-8, nonblank query lines before compilation, including queries that subsequently fail.
Keep duplicates and preserve query whitespace after removing the physical line ending.
Exclude blank lines, all session commands including unknown commands, and invalid UTF-8 input.
Discard the oldest query after inserting entry 501.
Start each session with empty history and discard its history on exit.
Create no history files and modify no shell configuration.
Disable automatic history persistence provided by the editor integration.

## Function completion

Get built-in names from `Functions.default.names` and metadata from its public metadata interface.
Reuse public signatures and descriptions for the function listing; completion candidates contain names only.
Completion never compiles or evaluates a query, invokes application callbacks, or reads document values.

Locate the ASCII function-name token containing the cursor using the line buffer and cursor position.
Use the token text before the cursor as the prefix; an empty prefix produces no candidates.
Recognize token characters as ASCII letters, digits, and underscores, with a letter or underscore at the start.
Replace the complete token while preserving every byte outside it, including Unicode content.
Suppress completion inside quoted identifiers, single-quoted strings, and backtick literals, accounting for their escape rules.
Offer no command-name or field-name completion.

Sort matching names lexically.
For one match, insert the complete name without parentheses or trailing whitespace.
For multiple matches, extend to their common prefix when possible.
When no extension is possible, display the sorted alternatives on stderr and leave the buffer unchanged.
For no matches, leave the buffer unchanged without diagnostics.
Treat completion as name assistance, not syntax validation; full query validation remains on submission.

## Commands and routing

Keep `:help` and `:quit` behavior and add `:functions`, `:explain QUERY`, and `:trace QUERY`.
Recognize command names after optional leading spaces or tabs, with an exact name boundary.
For argument commands, consume the separating spaces or tabs and preserve the complete remaining query, including trailing whitespace.
Source locations refer to that query, excluding the command prefix.
Whitespace-only arguments produce a missing-query diagnostic.
Reject surplus arguments to commands that accept none, leaving the session usable.
Unknown commands retain escaped diagnostics through `FailureDiagnostic`.

`:functions` renders `FunctionListing.render(Functions.default)` to stderr.
`:explain` compiles once and renders `Expression#explain` without evaluating the loaded document.
Unknown function names can appear in explanations because structural inspection does not resolve functions.
`:trace` compiles once and calls `Expression#trace` once with `limit: 1000`.
Never run an additional ordinary search to obtain the traced result.
Serialize the report's value completely before writing the report or result.
Write the report to stderr, then write the successful compact JSON value once to stdout and flush it.
Null and false are successful values.

Recover from query syntax, type, arity, unknown-function, and JSON serialization failures through established diagnostics.
Failed commands emit no result and accept the next line.
Input, output, prompt, and diagnostic IO failures terminate with status 1 without retrying failed writes.
EOF and `:quit` return status 0 after recoverable failures.
Startup failures retain status 1; invalid CLI arguments retain status 2.

## Readable reports

Render explanations as deterministic indented text in public child order.
Each node shows its operation ID, operation name, source location, and operation-specific details.
Show child roles so predicates, projection bodies, and expression arguments remain distinguishable.
Use public byte ranges to derive one-based character columns, accounting for Unicode.
Show unavailable locations explicitly when public ranges are nil.
Escape control characters in user text and literal details to prevent terminal control sequences.

Render trace events in report order with their public event type, operation ID, details, and enclosing iteration context.
Resolve source locations through the same expression's explanation, without reevaluation.
Include `field_null`, `filter_exclusion`, and `projection_omission`, retaining public reason values and zero-based context indexes.
Print a concise no-events message for an empty successful trace.
When truncated, state that only the first 1,000 events are shown and evaluation completed.
Do not claim a total event count that the public report does not provide.
Keep text layout private; the public Ruby APIs remain the structured inspection interface.

## Delivery and verification

1. Add terminal selection, the Reline adapter, editing, cancellation, cleanup, and bounded session history.
2. Add cursor-aware function completion with quote handling and deterministic candidate behavior.
3. Add inspection commands, readable reports, and their help and reference documentation.

Keep each delivery independently usable, tested, and documented.
Update `:help`, interactive topic help, the command-line guide, relevant README links, and compilation guidance as behavior becomes available.
Document supported terminal behavior, history lifetime, completion rules, routing, limits, fallback, and verified platform boundaries.
Retain both executable names, all argument rules, compact results, Unicode, flushing, CRLF, final unterminated lines, and invalid UTF-8 recovery.
Update private RBS declarations and packaging checks when needed.

Use failing regressions before implementation and preserve unrelated tests and imported fixtures.
Use injected streams to verify that pipes never initialize Reline or require terminal methods.
Verify history order, eviction, invalid-query recall, duplicates, session isolation, and the absence of history writes.
Verify completion at the cursor, token suffix replacement, Unicode preservation, escaped quotes, ambiguity, and no matches.
Use spies or guarded objects to prove completion and explanation do not evaluate or inspect document values.
Verify source locations, trace parity, one evaluation, one JSON result, truncation, diagnostic recovery, and stream failures.

Exercise editing, recall, completion, Ctrl-C, EOF, and terminal cleanup through a real or pseudo terminal.
Test both executables and inspect terminal attributes before and after successful and failed sessions.
Run supported Ruby versions through CI and include Linux and macOS terminal coverage where available.
Do not claim Windows or visual terminal verification without direct evidence.

Run `env RUBOCOP_CACHE_ROOT=/private/tmp/jmespath-rubocop-cache bundle exec rake` and `bundle exec rake docs`.
Run `bundle exec rake audit` separately and report its outcome independently.
Helper names, exact report punctuation, compatible dependency constraints, and fixture organization remain builder decisions.
Approval authorizes an implementation plan; it does not authorize product implementation, publication, or remote repository operations by itself.
