# frozen_string_literal: true

require_relative "../support/wrappers"

RSpec.describe "JMESPath values" do
  it "uses language truthiness rather than Ruby truthiness" do
    [nil, false, "", [], {}, Arrayish.new([]), Hashish.new({})].each do |value|
      expect(JMESPath::Types.falsey?(value)).to be(true)
    end
    [0, true, "a", [nil], { x: nil }].each do |value|
      expect(JMESPath::Types.falsey?(value)).to be(false)
    end
  end

  it "compares numeric values without conflating booleans" do
    expect(JMESPath::Types.equal?({ "x" => [1] }, { "x" => [1.0] })).to be(true)
    expect(JMESPath::Types.equal?([true], [1])).to be(false)
    expect(JMESPath::Types.equal?({ x: 1 }, { "x" => 1 })).to be(false)
  end

  it "unwraps protocol objects for structural equality" do
    expect(JMESPath::Types.equal?(Arrayish.new([1]), [1])).to be(true)
  end

  it "detects cycles while allowing repeated acyclic objects" do
    first = []
    first << first
    second = []
    second << second
    expect { JMESPath::Types.equal?(first, second) }.to raise_error(JMESPath::Errors::InvalidValueError)
    item = [1]
    expect(JMESPath::Types.equal?([item, item], [[1], [1]])).to be(true)
  end

  it "evaluates expression references against their argument" do
    reference = JMESPath::ExpressionReference.new { |value| value.fetch("x") }
    expect(reference.call({ "x" => 7 })).to eq(7)
    expect(JMESPath::Types.name(reference)).to eq(:expref)
  end

  it "classifies the supported language types" do
    values = [nil, false, 1, 1.5, "x", [], {}, Struct.new(:x).new(1), Object.new]
    expect(values.map { |value| JMESPath::Types.name(value) }).to eq(
      %i[null boolean number number string array object object unknown]
    )
  end
end
