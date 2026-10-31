# frozen_string_literal: true

RSpec.describe "Custom function registries" do
  let(:empty) { JMESPath::Functions.new }
  let(:registry) { empty.with("double", signature: [[:number]]) { |number| number * 2 } }

  it "calls a declared function without changing the parent registry" do
    expect(registry.call("double", [3])).to eq(6)
    expect { empty.call("double", [3]) }.to raise_error(JMESPath::Errors::UnknownFunctionError)
  end

  it "validates types and arity" do
    expect { registry.call("double", [true]) }.to raise_error(JMESPath::Errors::InvalidTypeError)
    expect { registry.call("double", []) }.to raise_error(JMESPath::Errors::InvalidArityError)
    expect(registry.call("double", [true], disable_visit_errors: true)).to be_nil
  end

  it "requires explicit replacement and leaves both registries immutable" do
    expect { registry.with("double", signature: [[:number]]) { 0 } }.to raise_error(ArgumentError)
    replacement = registry.with("double", signature: [[:number]], override: true) { 0 }
    expect(replacement.call("double", [3])).to eq(0)
    expect(registry.call("double", [3])).to eq(6)
    expect(registry).to be_frozen
  end

  it "preserves callback failures even when visit errors are disabled" do
    error = JMESPath::Errors::InvalidTypeError.new("callback defect")
    failure = empty.with("explode", signature: []) { raise error }
    expect { failure.call("explode", [], disable_visit_errors: true) }.to(raise_error do |raised|
      expect(raised).to equal(error)
      expect(raised.backtrace.first).to include("functions_spec")
    end)
  end

  it "rejects malformed definitions" do
    expect { empty.with("bad name", signature: []) { nil } }.to raise_error(ArgumentError)
    expect { empty.with("missing", signature: []) }.to raise_error(ArgumentError)
    expect { empty.with("bad", signature: [[:unknown]]) { nil } }.to raise_error(ArgumentError)
    expect { empty.with("bad", signature: [], variadic: true) { nil } }.to raise_error(ArgumentError)
  end
end

RSpec.describe "Invalid custom function definitions" do
  it "rejects names that cannot resolve from query text" do
    [:example, nil, 42].each do |name|
      expect { JMESPath::Functions.new.with(name, signature: []) { 1 } }.to raise_error(ArgumentError)
    end
  end

  it "rejects malformed signature containers with the documented error" do
    [nil, "number", [nil], [1], [["number"]]].each do |signature|
      expect { JMESPath::Functions.new.with("example", signature: signature) { 1 } }.to raise_error(ArgumentError)
    end
  end
end
