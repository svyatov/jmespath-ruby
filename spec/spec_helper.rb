# frozen_string_literal: true

require "simplecov"
SimpleCov.merging false
SimpleCov.start do
  enable_coverage :branch
  cover "lib/**/*.rb"
end

require "jmespath"
