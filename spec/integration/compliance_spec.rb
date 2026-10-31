# frozen_string_literal: true

require_relative "../support/compliance"

RSpec.describe "Pinned JMESPath compliance" do
  include ComplianceFixtures

  ComplianceFixtures.cases.each do |entry|
    it(entry.fetch(:id)) { assert_compliance(entry) }
    next if entry[:error]

    it("#{entry.fetch(:id)} with Ruby wrappers") { assert_compliance(entry, wrapped: true) }
  end
end
