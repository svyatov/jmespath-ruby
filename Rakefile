# frozen_string_literal: true

require "rspec/core/rake_task"

task :coverage do
  ENV["COVERAGE"] = "1"
end
RSpec::Core::RakeTask.new(:spec)
task spec: :coverage
Dir[File.join(__dir__, "tasks/*.rake")].each { |path| load path }
task default: %i[lint types spec crap docs:check]
