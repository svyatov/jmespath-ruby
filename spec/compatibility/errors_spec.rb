# frozen_string_literal: true

require_relative "../support/compliance"

RSpec.describe "Compatible visit-error suppression" do
  include ComplianceFixtures

  ComplianceFixtures.cases.select { |entry| entry[:error] }.each do |entry|
    it(entry.fetch(:id)) { assert_compliance(entry, suppress: true) }
  end
end
