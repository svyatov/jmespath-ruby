# frozen_string_literal: true

require_relative "lib/jmespath/version"

Gem::Specification.new do |spec|
  spec.name = "jmespath-ruby"
  spec.version = JMESPath::VERSION
  spec.authors = ["Leonid Svyatov"]
  spec.summary = "A typed Ruby implementation of the JMESPath query language"
  spec.description = "Search structured Ruby data with reusable JMESPath expressions."
  spec.license = "MIT"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.required_ruby_version = ">= 3.3"
  spec.files = Dir["lib/**/*.rb", "sig/jmespath.rbs", "exe/*", "README.md", "LICENSE", "LICENSES/*", "docs/guides/*.md"]
  spec.require_paths = ["lib"]
  spec.bindir = "exe"
  spec.executables = Dir["exe/*"].map { |path| File.basename(path) }
  spec.add_dependency "json", ">= 2.7", "< 4"
  spec.add_dependency "stringio", ">= 3.0", "< 4"
end
