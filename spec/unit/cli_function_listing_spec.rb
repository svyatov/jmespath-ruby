# frozen_string_literal: true

require "jmespath/cli"

RSpec.describe "CLI function signature formatting" do
  [
    [[], false, "sample() Sample."],
    [[%i[string null]], true, "sample((string|null)...) Sample."],
    [[[:boolean], [:array_number], [:any]], true, "sample(boolean, array<number>, any...) Sample."],
    [[[:array_string], %i[number null]], false, "sample(array<string>, number|null) Sample."]
  ].each do |signature, variadic, expected|
    it "renders #{expected}" do
      registry = JMESPath::Functions.new.with("sample", signature: signature, variadic: variadic,
                                                        description: "Sample.") { raise "Callback invoked" }
      expect(JMESPath::CLI::FunctionListing.render(registry).lines.first).to eq("#{expected}\n")
    end
  end

  it "renders the legend after the separator for an empty registry" do
    expect(JMESPath::CLI::FunctionListing.render(JMESPath::Functions.new)).to eq(
      "\nTypes: any accepts any value; A|B accepts either type.\n" \
      "array<T> requires every element to have type T; array is unrestricted.\n" \
      "expref is an expression reference, written &expression.\n" \
      "T... requires one or more arguments of type T.\n" \
      "Signatures describe declared argument types; runtime checks can be narrower.\n"
    )
  end

  it "rejects inconsistent metadata rather than silently omitting a listed function" do
    registry = instance_double(JMESPath::Functions, names: ["missing"], metadata: nil)
    expect { JMESPath::CLI::FunctionListing.render(registry) }
      .to raise_error(RuntimeError, "Missing function metadata: missing")
  end
end
