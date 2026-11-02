# Shell completion

The gem includes Bash and Zsh completion definitions for `jmespath` and `jmespath.rb`.
They suggest option names and filesystem paths after `--file` and `--query-file`.
Both `--file PATH` and `--file=PATH` forms support completion, including spaces in filenames.

## Bash setup

Run these commands in the Bash session and Ruby environment where you use the gem:

```bash
jmespath_gem_root="$(ruby -rrubygems -e 'print Gem::Specification.find_by_name("jmespath-ruby").full_gem_path')"
source "$jmespath_gem_root/completions/jmespath.bash"
```

The definition uses Bash built-ins and supports Bash 3.2 or later.
It requires no completion framework.

## Zsh setup

Add the gem's completion directory to `fpath` before initializing completion:

```zsh
jmespath_gem_root="$(ruby -rrubygems -e 'print Gem::Specification.find_by_name("jmespath-ruby").full_gem_path')"
fpath=("$jmespath_gem_root/completions" $fpath)
autoload -Uz compinit
compinit
```

If completion is initialized in the session, run these commands again to register the added definition.
The definition uses Zsh's standard completion system.

## Persistent setup

To enable completion in later sessions, add the relevant setup commands to your shell startup file yourself.
For Zsh, place the `fpath` assignment before your startup file's `compinit` call.
Installation does not edit shell configuration.

When the gem is available only through Bundler, replace `ruby` in the lookup command with `bundle exec ruby`.
Use the Ruby environment and gem version that supply your executable.
After changing Ruby environments or gem versions, load the matching completion definition again.

## Usage and boundaries

Press Tab while entering an option or path.
These examples show the key as `<Tab>`:

```text
jmespath --que<Tab>
jmespath --query-file queries/rep<Tab>
jmespath.rb --file=my<Tab>
```

Directories remain available for further path completion, without filtering by file extension.
Paths containing spaces receive shell quoting, so the completed path remains one argument.
Hyphen-leading filenames follow the CLI's literal-path rules, such as `--file=--document.json` or `--file ./--document.json`.

Options remain available before or after an expression until a standalone `--` delimiter.
Repeated or conflicting options remain visible; the CLI validates combinations when you run the command.
Completion does not suggest JMESPath expressions or complete arguments after the delimiter.
It lists filesystem names without running the CLI, evaluating queries, or reading document or query contents.
Ruby runs only during the installation-path lookup shown above.

Fish support and automatic installation are outside this feature.
