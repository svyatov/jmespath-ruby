# frozen_string_literal: true

require "digest"
require_relative "../support/compliance"

RSpec.describe "Pinned fixture integrity" do
  include ComplianceFixtures

  it "detects a wrong expected result" do
    wrong = { given: { "x" => 1 }, expression: "x", result: 2 }
    expect { assert_compliance(wrong) }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  manifest = JSON.parse(File.read(File.join(ComplianceFixtures::ROOT, "sources.json")))
  manifest.fetch("sources").each do |source|
    it("preserves #{source.fetch('local_path')}") do
      file = File.expand_path("../../#{source.fetch('local_path')}", __dir__)
      expect(Digest::SHA256.file(file).hexdigest).to eq(source.fetch("sha256"))
    end
  end
end
