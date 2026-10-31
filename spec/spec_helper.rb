# frozen_string_literal: true

require "simplecov"
coverage_file = File.expand_path("../coverage/.resultset.json", __dir__)
File.delete(coverage_file) if File.file?(coverage_file)
SimpleCov.merging true
SimpleCov.start do
  enable_coverage :branch
  cover "lib/**/*.rb"
  if ENV["COVERAGE"] == "1"
    coverage :line, minimum: 100
    coverage :branch, minimum: 100
  end
end

require "jmespath"
