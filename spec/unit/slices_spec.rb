# frozen_string_literal: true

require_relative "../support/evaluate"

RSpec.describe "Array slices" do
  {
    "[::-1]" => [4, 3, 2, 1, 0],
    "[0:0:-1]" => [],
    "[:0:-1]" => [4, 3, 2, 1],
    "[:-1:-1]" => [],
    "[:]" => [0, 1, 2, 3, 4],
    "[1:4:2]" => [1, 3],
    "[-99:99]" => [0, 1, 2, 3, 4],
    "[99:-99:-2]" => [4, 2, 0],
    "[5:0]" => []
  }.each do |query, expected|
    it("normalizes #{query}") { expect(evaluate(query, [0, 1, 2, 3, 4])).to eq(expected) }
  end

  it "returns nil for non-arrays and an empty result for empty arrays" do
    expect(evaluate("[:]", {})).to be_nil
    expect(evaluate("[::-1]", [])).to eq([])
  end

  it "rejects a zero step when constructed directly" do
    expect { JMESPath::Slice.new(start: nil, stop: nil, step: 0) }
      .to raise_error(JMESPath::Errors::InvalidValueError, "Slice step cannot be zero")
  end
end
