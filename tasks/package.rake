# frozen_string_literal: true

require_relative "../script/support/package_check"

desc "Build the installable gem"
task :build do
  checker = PackageCheck.new(File.expand_path("..", __dir__))
  checker.build("pkg")
end

namespace :package do
  desc "Verify an offline production-only installation of the built gem"
  task check: :build do
    checker = PackageCheck.new(File.expand_path("..", __dir__))
    artifact = Dir["pkg/jmespath-ruby-*.gem"].max_by { |path| File.mtime(path) }
    puts JSON.pretty_generate(checker.verify(artifact))
  end
end
