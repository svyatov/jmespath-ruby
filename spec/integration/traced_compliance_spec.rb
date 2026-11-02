# frozen_string_literal: true

require_relative "../support/compliance"

RSpec.describe "Traced pinned JMESPath compliance" do
  ComplianceFixtures.cases.each do |entry|
    it(entry.fetch(:id)) do
      operation = lambda do |data|
        JMESPath.compile(entry.fetch(:expression)).trace(data)[:value]
      end
      if entry[:error]
        expect { operation.call(entry.fetch(:given)) }.to raise_error(ComplianceFixtures::ERRORS.fetch(entry[:error]))
      else
        [entry.fetch(:given), ComplianceFixtures.wrap(entry.fetch(:given))].each do |data|
          original = Marshal.dump(data)
          expect(JMESPath::Types.normalize(operation.call(data))).to eq(entry[:result])
          expect(Marshal.dump(data)).to eq(original)
        end
      end
    end
  end
end
