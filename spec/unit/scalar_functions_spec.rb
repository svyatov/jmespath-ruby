# frozen_string_literal: true

require_relative "../support/evaluate"

RSpec.describe "Scalar built-in functions" do
  let(:registry) { JMESPath::Functions::Scalar.register(JMESPath::Functions.new) }

  {
    ["abs", [-2]] => 2,
    ["ceil", [1.2]] => 2,
    ["floor", [1.8]] => 1,
    ["contains", [[{ "x" => 1 }], { "x" => 1 }]] => true,
    ["ends_with", %w[café fé]] => true,
    ["starts_with", %w[café ca]] => true,
    ["length", ["✓é"]] => 2,
    ["reverse", ["abc"]] => "cba",
    ["type", [false]] => "boolean",
    ["to_array", [nil]] => [nil],
    ["to_string", [{ "x" => false }]] => '{"x":false}',
    ["to_number", ["12.5"]] => 12.5,
    ["to_number", [true]] => nil,
    ["to_number", ["0x10"]] => nil,
    ["to_number", ["NaN"]] => nil,
    ["not_null", [nil, false, 3]] => false
  }.each do |(name, arguments), expected|
    it("evaluates #{name}(#{arguments.inspect})") { expect(registry.call(name, arguments)).to eq(expected) }
  end

  %w[abs ceil floor contains ends_with starts_with length reverse type to_array to_string to_number
     not_null].each do |name|
    it("rejects missing arguments for #{name}") do
      expect { registry.call(name, []) }.to raise_error(JMESPath::Errors::InvalidArityError)
    end
  end

  %w[abs ceil floor contains ends_with starts_with length reverse].each do |name|
    it("rejects incompatible input for #{name}") do
      args = %w[contains ends_with starts_with].include?(name) ? [nil, nil] : [nil]
      expect { registry.call(name, args) }.to raise_error(JMESPath::Errors::InvalidTypeError)
      expect(registry.call(name, args, disable_visit_errors: true)).to be_nil
    end
  end

  it "enforces the corrected function arities" do
    expect { registry.call("reverse", %w[a b]) }.to raise_error(JMESPath::Errors::InvalidArityError)
    expect { registry.call("to_array", []) }.to raise_error(JMESPath::Errors::InvalidArityError)
  end

  it "validates string containment and propagates invalid-value failures" do
    expect { registry.call("contains", ["abc", 2]) }.to raise_error(JMESPath::Errors::InvalidTypeError)
    cyclic = {}
    cyclic["self"] = cyclic
    expect { registry.call("to_string", [cyclic]) }.to raise_error(JMESPath::Errors::InvalidValueError)
  end

  it "uses the parser and evaluator with the built-in registry" do
    expect(evaluate("not_null(a, b, c)", { a: nil, b: false, c: 3 }, functions: registry)).to be(false)
  end
end
