# frozen_string_literal: true

desc "Check Ruby correctness and style"
task :lint do
  sh "bundle", "exec", "rubocop"
end

desc "Check RBS signatures and implementation types"
task :types do
  sh "bundle", "exec", "rbs", "-I", "sig", "validate"
  sh "bundle", "exec", "steep", "check"
end

desc "Measure complexity against fresh test coverage"
task crap: :spec do
  sh "bundle", "exec", "crap4ruby", "lib", "--coverage", "coverage/.resultset.json", "--threshold", "10", "--no-save"
end

desc "Refresh advisory data and audit the locked bundle"
task :audit do
  sh "bundle", "exec", "bundle-audit", "check", "--update"
end
