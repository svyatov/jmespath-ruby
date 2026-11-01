# Development

Use Ruby 3.3 or later.
Install the locked development bundle with `bundle install`.

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
The release workflow runs the full quality matrix, verifies the tag, archives the built gem, and publishes through RubyGems trusted publishing.

The trusted publisher is restricted to `svyatov/jmespath-ruby`, workflow `release.yml`, and GitHub environment `release`.
The environment accepts release tags matching `v*`.
The token exchange declares the account's immutable RubyGems owner ID, `71752`, which is required for the first publication.
No long-lived RubyGems API key is required.
After publication, create the GitHub release from the archived gem and its matching changelog entry.
If only GitHub release creation fails, reuse that artifact; do not republish the gem.
