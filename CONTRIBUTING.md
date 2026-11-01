# Development

Use Ruby 3.3 or later.
Install the locked development bundle with `bundle install`.

Outside contributions are welcome. This guide is the project's contribution standard.

## Submit a change

Fork the repository and create a branch from `main`.
Use a branch name such as `fix/query-validation` and Conventional Commits for commit messages.
Keep each pull request focused on one change.
Open a pull request against `main` describing the problem, the change, and any public API consequences.

New functionality must include tests. Bug fixes must include a regression test that fails before the fix.
Follow the checks, fixture rules, and documentation requirements in this guide.
Follow [VERSIONING.md](VERSIONING.md) when changing the public contract.
Participants must follow the [code of conduct](CODE_OF_CONDUCT.md).

## Decisions and continuity

Leonid Svyatov is the sole maintainer and decides which changes to accept, merge, and release.
No successor is arranged if he stops maintaining the project.

## Checks

```sh
bundle exec rake
bundle exec rake docs
bundle exec rake audit
```

The default task runs RuboCop, RBS validation, Steep, RSpec, fresh coverage, CRAP analysis, and documentation checks.
Coverage requires 100% lines and branches.
Every measurable library method must score at most 10 in coverage-aware CRAP analysis.
A missing coverage report fails the check.
Unmeasurable methods are reported for review.
CI reports existing dependency advisories without blocking unrelated changes.
Dependency review blocks pull requests that introduce known vulnerabilities.

Run `bundle exec rspec spec/unit/parser_spec.rb` for a focused test cycle.
Focused RSpec runs collect coverage without enforcing full-suite thresholds.
Keep expected values independent of implementation code.
Add a failing regression test before fixing behavior.

## Compatibility fixtures

Imported fixtures live under `spec/fixtures/upstream`.
Their manifest records source commits, paths, licenses, and SHA-256 hashes.
Preserve imported bytes.
Place local regression cases and supplemental benchmark expectations outside the imported files.

Use `script/differential.rb` with explicit pinned reference checkouts for comparisons.
Normal tests require neither network access nor Python.

## Documentation and releases

Write YARD types and executable examples for public APIs.
Examples ending in `#=>` or `# raises ErrorClass` run through documentation checks.
Keep private implementation surfaces marked with `@api private`.

Use Conventional Commits and focused commits.
Build and validate an isolated gem before a release.
Publishing and remote repository operations require separate authorization.

## Release

Update `lib/jmespath/version.rb` and `CHANGELOG.md` together.
Run `bundle exec rake release:check` before creating a release tag.
Push a `vVERSION` tag that exactly matches `JMESPath::VERSION`.
The release workflow runs the quality matrix and builds the gem, dependency inventory, checksums, and changelog-derived release notes.
It verifies the tag before publication and publishes the exact archived gem through RubyGems trusted publishing after manual approval.
It uploads provenance to RubyGems and attaches the attested gem, inventory, and checksums to the GitHub release.

The trusted publisher is restricted to `svyatov/jmespath-ruby`, workflow `release.yml`, and GitHub environment `release`.
The environment accepts release tags matching `v*`.
The token exchange declares the account's immutable RubyGems owner ID, `71752`, which is required for the first publication.
No long-lived RubyGems API key is required.
Use manual workflow dispatch on a branch to verify and build without publishing.
If only GitHub release creation fails, rerun the failed job to reuse the archived artifact; do not republish the gem.
