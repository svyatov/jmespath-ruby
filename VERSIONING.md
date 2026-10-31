# Versioning

The initial package version is 0.1.0.
The public contract includes the documented Ruby API, language behavior, error categories, options, CLI, and minimum Ruby version.
Private implementation classes are outside that contract.

Before 1.0, a breaking public change requires a minor version.
After 1.0, a breaking public change requires a major version.
Dropping Ruby 3.3 support after 1.0 requires a major release.

Document corrected reference defects and migration consequences in the changelog.
A tag or successful build alone does not establish publication.
