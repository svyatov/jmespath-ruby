# frozen_string_literal: true

RSpec.describe "Function argument signatures" do
  it "checks every variadic argument" do
    registry = JMESPath::Functions.new.with("sum", signature: [[:number]], variadic: true) { |*args| args.sum }
    expect(registry.call("sum", [1, 2, 3])).to eq(6)
    expect { registry.call("sum", [1, 2, "bad"]) }.to raise_error(JMESPath::Errors::InvalidTypeError)
    expect { registry.call("sum", []) }.to raise_error(JMESPath::Errors::InvalidArityError)
  end

  it "accepts unions of homogeneous array types" do
    registry = JMESPath::Functions.new.with("list", signature: [%i[array_number array_string]]) { |value| value }
    expect(registry.call("list", [[]])).to eq([])
    expect(registry.call("list", [[1, 2]])).to eq([1, 2])
    expect(registry.call("list", [%w[a b]])).to eq(%w[a b])
    expect { registry.call("list", [[1, "b"]]) }.to raise_error(JMESPath::Errors::InvalidTypeError)
  end

  it "rejects non-finite numbers" do
    registry = JMESPath::Functions.new.with("number", signature: [[:number]]) { |value| value }
    expect { registry.call("number", [Float::INFINITY]) }.to raise_error(JMESPath::Errors::InvalidTypeError)
  end
end
