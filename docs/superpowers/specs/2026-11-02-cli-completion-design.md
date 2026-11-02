# CLI shell completion

Status: approved by the user on 2026-11-02.
Scope: [issue #27](https://github.com/svyatov/jmespath-ruby/issues/27).

## Intent and boundaries

Provide Bash and Zsh users with option and filename completion for both `jmespath` and `jmespath.rb`.
Preserve CLI behavior, public Ruby interfaces, and standard JMESPath semantics.
Exclude expression completion, Fish support, automatic installation, completion frameworks, and filtering conflicting options.
Completion must never execute either CLI executable, evaluate queries, or read document or query contents.

## Approaches

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| O1: Suggest all supported options | Small shell definitions with limited argument tracking | Can suggest invalid option combinations | Selected by the user |
| O2: Hide conflicting options | Avoids some invalid combinations | Duplicates CLI validation rules in both shells | Rejected |

The user selected O1 because conflict filtering exceeds the issue's requirements and adds maintenance.

## Completion behavior

Register identical behavior for both executable names.
Suggest implemented, documented option spellings when the current word begins with `-`.
Offer options before or after a positional expression until the standalone `--` delimiter.
After that delimiter, offer neither options nor expression completions.

Complete filesystem paths after `--file` and `--query-file`, including their `--option=value` forms.
Support spaces, shell quoting, nested paths, and directory traversal without filtering by extension.
Treat a path being completed as an option value, including paths beginning with a hyphen.
Leave positional expressions without completion candidates.
Keep repeated and conflicting options available under O1.
Cover the implemented CLI when building the change; approved but unimplemented flags are outside this change.

## Assets and installation

Proposed implementation choice: ship static definitions at `completions/jmespath.bash` and `completions/_jmespath`.
Use Bash built-ins compatible with Bash 3.2 and Zsh's standard completion system, without external frameworks.
Do not invoke Ruby during completion or generate candidates from CLI output.
Add both files to the gemspec's explicit package patterns.

Document manual installation in `docs/guides/completion.md`, linked from the README and CLI help.
Show how to locate the installed gem's completion files.
For Bash, document sourcing the definition in a session.
For Zsh, document placing the definition on `fpath` before initializing completion with `compinit`.
Explain optional persistent setup for users to perform themselves; installation must not edit shell configuration.

## Verification

Add failing regressions before implementation.
Exercise both command names, option prefixes, option ordering, delimiters, and both path-value forms in each shell.
Verify candidate boundaries and quoting for filenames containing spaces, including nested directories and option-like names.
Check option definitions against implemented CLI options so additions or removals require completion updates.
Run syntax checks and behavior tests with installed shells; explicitly report any unavailable shell verification.
Verify completion succeeds with CLI execution blocked and input contents unreadable.
Assert both assets and the installation guide appear in a built gem, and exercise the packaged definitions.
Run `bundle exec rake` and `bundle exec rake docs`.

## Builder decisions

Private shell function names, test harness details, and directory-completion mechanics remain implementation decisions.
No public Ruby API or dependency changes are required.
