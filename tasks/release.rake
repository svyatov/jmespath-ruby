# frozen_string_literal: true

namespace :release do
  desc "Run local release checks without publishing"
  task check: [:default, :docs, "package:check", :audit]
end
