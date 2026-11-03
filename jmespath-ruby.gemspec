# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "jmespath-ruby"
  spec.version = File.read(File.join(__dir__, "lib/jmespath/version.rb"))[/VERSION = "([^"]+)"/, 1]
  spec.authors = ["Leonid Svyatov"]
  spec.summary = "A typed Ruby implementation of the JMESPath query language"
  spec.description = "Search structured Ruby data with reusable JMESPath expressions."
  spec.homepage = "https://github.com/svyatov/jmespath-ruby"
  spec.license = "MIT"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.required_ruby_version = ">= 3.3"
  spec.files = Dir["lib/**/*.rb", "sig/jmespath.rbs", "exe/*", "README.md", "CONTRIBUTING.md", "CHANGELOG.md",
                   "VERSIONING.md",
                   "SECURITY.md", "LICENSE", "LICENSES/*", "docs/guides/*.md",
                   "completions/jmespath.bash", "completions/_jmespath"]
  spec.require_paths = ["lib"]
  spec.bindir = "exe"
  spec.executables = Dir["exe/*"].map { |path| File.basename(path) }
  spec.add_dependency "json", ">= 2.7", "< 4"
  spec.add_dependency "reline", "~> 0.7.0"
  spec.add_dependency "stringio", ">= 3.0", "< 4"
end
