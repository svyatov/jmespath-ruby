# frozen_string_literal: true

namespace :docs do
  desc "Check public API documentation, links, and examples"
  task :check do
    ruby "script/check_docs.rb"
  end
end

desc "Generate YARD HTML documentation"
task :docs do
  sh "bundle", "exec", "yard", "doc", "--fail-on-warning"
end
