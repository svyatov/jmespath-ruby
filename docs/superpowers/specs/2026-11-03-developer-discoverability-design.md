# Developer documentation and CLI help

Status: approved by the user on 2026-11-03.
Scope: [issue #52](https://github.com/svyatov/jmespath-ruby/issues/52).

## Intent

Help developers reach a working example before reading detailed reference rules.
Serve Ruby library users first while keeping shell tasks directly accessible.
Preserve the documented replacement contract for jmespath.rb and every query execution contract.

The user selected Ruby-first documentation and A1: one CLI guide with topic help.
This is a documentation and CLI project delivered in two independently usable changes.

## Goals and boundaries

Provide one short example for each common task and direct links to its detailed reference.
Keep installation, migration warnings, and provider selection visible near the beginning.
Make default help suitable for finding options and common commands.
Provide complete offline reference rules through topic help.

Exclude query methods, language changes, execution changes, dependencies, editor integrations, and browser tools.
Keep benchmark methodology and recorded measurements unchanged.
Interactive enhancements from issue #53 remain separate.
A shorter README that loses a contract or hides a migration warning fails this design.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| A1: One command-line guide plus topic help | Keeps shared mode rules in one reference | Guide and help text require coordinated updates | Selected by the user |
| A2: Separate guides for each CLI topic | Gives each topic a narrow page | Spreads shared rules across pages and adds navigation | Not selected |

Ruby-first ordering was selected over shell-first ordering or equal entry points before the first example.
A small task table follows the first Ruby example.

## README structure

Use this order, with descriptive headings and direct guide links:

1. Introduce the library and its Ruby requirement, then show installation and the first `JMESPath.search` example.
2. Provide a task table linking to the six common tasks below.
3. Explain replacement of jmespath.rb, including the Gemfile change and its limits.
4. Show the remaining task examples, followed by concise custom-function and discovery examples.
5. Link performance claims to detailed guides, then retain guides, maintenance, verification, and license information.

The task table and examples cover these interfaces:

| Task | Example interface | Detailed reference |
| --- | --- | --- |
| Search Ruby data | `JMESPath.search` | `search.md` |
| Reuse a query | `JMESPath.compile` and `Expression#search` | `compilation.md` |
| Require a non-null result | `Expression#fetch` | `compilation.md#required-results` |
| Handle an evaluation failure | `Expression#try_search` | `errors.md#failure-results` |
| Debug an unexpected result | `Expression#trace` and `Expression#explain` | The tracing and inspection sections in `compilation.md` |
| Search a JSON document from the shell | `jmespath --file PATH EXPRESSION` | `command-line.md` |

Keep the package-name warning and the instruction to select one provider per bundle in the migration section.
Retain stricter-validation and private-interface limits through a concise explanation and the compatibility guide link.
Place extended benchmark tables and discussion in the comparison and performance guides.
Retain discoverable links to function registration, metadata, syntax validation, and diagnostics.
Preserve useful README fragment links where practical; anchor preservation is a builder decision, not a public compatibility promise.

## Command-line guide

Create `docs/guides/command-line.md` as the complete CLI reference for both executable names.
Use stable sections for quick start, input, output, validation, functions, interactive sessions, and exit statuses.
Link completion setup to `completion.md` and diagnostic details to `errors.md`.
Keep function signature notation authoritative in `functions.md`, with a direct link from the guide.

Before moving prose, inventory every CLI contract in the README and help text.
Record each destination in the implementation plan and verify the inventory after the move.
Retain unique facts from either source, even when wording is consolidated.
Resolve conflicting descriptions against tested behavior and flag any conflict that would require a behavior change.

The inventory must include literal paths, option-like filenames, exact names, option placement, delimiters, and repeated or conflicting options.
It must include query-file encoding, source preservation, input ordering, file closure, and caller-owned streams.
It must include output newlines, JSON Lines partial failures, buffering, and interactive recovery and termination.
It must include validation precedence, information-mode independence, diagnostics, and mode-specific exit statuses.

Include the guide in `.yardopts` and the README guide index.
The gemspec's `docs/guides/*.md` pattern already includes the file; verify the built artifact explicitly.
Add referenced comparison and completion guides to generated documentation if needed to keep the guide navigation usable.

## Default and topic help

Both executables produce identical help text.
Default `--help` and `-h` show usage forms, every public option name, common examples, and all five topic commands.
List `-h`, `--help`, `--version`, `--functions`, `--file`, `--query-file`, `--validate`, `--pretty`, `--raw-output`, `--json-lines`, and `--interactive`.
Do not document private completion switches or accidental option spellings as public interfaces.
Keep detailed restrictions and function type notation out of default help.

Support these exact topic names:

| Topic command | Contents |
| --- | --- |
| `jmespath --help input` | Document and query sources, UTF-8, literal paths, quoting, option parsing, ordering, ownership, and input failures |
| `jmespath --help output` | Compact, pretty, raw, and JSON Lines output; newlines, conflicts, partial failures, buffering, and statuses |
| `jmespath --help validate` | Syntax-only checks, literal validation precedence, query files, restrictions, diagnostics, and statuses |
| `jmespath --help functions` | Listing examples, restrictions, metadata descriptions, type notation, runtime validation, and statuses |
| `jmespath --help interactive` | Startup, commands, streams, prompts, recovery, termination, limitations, and statuses |

Each topic is usable offline and contains examples, restrictions, stream behavior, and applicable exit statuses.
Include a reference to the packaged command-line guide and its repository URL for extended reading.
Preserve the full function listing and its notation legend under `--functions`.
Preserve in-session `:help`; this issue changes startup help only.

The following details are proposals for approval, selected by the author:

- Accept `-h TOPIC` as an alias of `--help TOPIC`, matching the default-help alias.
- Accept help only as the first argument, followed by zero or one exact topic name.
- Topic names are case-sensitive; abbreviations, equals forms, unknown topics, and surplus arguments are usage failures.
- Usage guidance on stderr includes a working pointer to `jmespath --help`.
- Keep help rendering separate from execution argument parsing; helper names and text storage remain builder decisions.

## Dispatch and failure contract

Preserve the exact two-argument literal-validation check before help dispatch.
Thus `jmespath --validate --help` validates the literal query `--help`, with its normal validation status and diagnostic.
Likewise, `--validate -h` retains literal validation.

Valid default and topic help write only to stdout and return status 0.
Unknown topics and surplus arguments return status 2, leave stdout empty, and write usage guidance to stderr.
Help requests, including invalid requests, never open document or query files or read stdin.
Output failures retain the CLI's status-1 failure handling.
Retain caller ownership of argument arrays and streams.

Preserve all non-help information modes, execution flags, defaults, strict matching, equals-value forms, and delimiter behavior.
Do not scan all arguments for help flags: a filename or a literal query can contain flag-like text.
Execution and interactive argument validation must reject unsupported help combinations before accessing any files or input.

## Completion

Extend Bash and Zsh completion for both executable names without invoking the CLI.
Offer the five topic names immediately after an initial `--help` or `-h`.
Filter topics by the typed prefix and offer no further arguments after a complete topic.
Preserve path completion, quoting, equals values, delimiters, and literal-validation behavior.
In particular, `--validate --help` must not enter topic completion.

## Delivery and verification

1. Reorganize the README and add the command-line guide, preserving the CLI behavior available in that change.
2. Add topic help, update guide wording for that syntax, relocate help assertions, and extend completion coverage.

Keep each change independently testable and each pull request focused.
The first change must not advertise unimplemented topic help.
No pull request, push, merge, or release is authorized by approval of this design alone.

Check Ruby examples with the executable documentation checker.
Run shell examples with small fixtures and compare actual output and statuses.
Check local file links and section anchors, since the documentation checker verifies file existence without checking fragments.
Verify every inventoried contract has a destination reachable from the README or help.

Add failing tests before changing help behavior.
Exercise both executables, all topics and aliases, invalid requests, output failures, and argument preservation.
Use input readers that raise on access and file-opening spies for successful and invalid help requests.
Retain strict-option, literal-validation, mode, and stream regression coverage.
Update prose-location assertions to check the appropriate topic while retaining their behavioral assertions.
Exercise Bash and Zsh topic completion for both executable names, including extracted gem definitions.
Assert the guide is packaged and generated documentation includes it.

Run `env RUBOCOP_CACHE_ROOT=/private/tmp/jmespath-rubocop-cache bundle exec rake` and `bundle exec rake docs`.
Run `bundle exec rake audit` separately, as required by CONTRIBUTING.md, and report its result independently.

Exact wording, helper organization, fixture layout, and focused test commands remain builder decisions.
No product code is implemented until this design is approved and an implementation plan is written.
