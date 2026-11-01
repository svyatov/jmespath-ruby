# frozen_string_literal: true

RSpec.describe "Unknown function suggestions" do
  def registry_with(*names)
    names.reduce(JMESPath::Functions.new) do |registry, name|
      registry.with(name, signature: []) { raise "Suggestion executed a callback" }
    end
  end

  def failure(registry, name)
    registry.call(name, [])
  rescue JMESPath::Errors::UnknownFunctionError => e
    e
  end

  {
    "dobule" => [%w[double], %w[double]],
    "abxc" => [%w[abc], %w[abc]],
    "abc" => [%w[abxc], %w[abxc]],
    "abxd" => [%w[abcd], %w[abcd]],
    "abxy" => [%w[abcd], []],
    "abcxy" => [%w[abcde], %w[abcde]],
    "abxyz" => [%w[abcde], []],
    "abcx" => [%w[abce abca abcd abcb], %w[abca abcb abcd]],
    "ABCD" => [%w[abcd], []],
    "Abcd" => [%w[abcd], %w[abcd]],
    "CAxyz" => [%w[ABCxyz], []]
  }.each do |name, (candidates, expected)|
    it "ranks #{name} against #{candidates.join(', ')}" do
      expect(failure(registry_with(*candidates), name).suggestions).to eq(expected)
    end
  end

  it "ranks by distance before lexical order and caps results at three" do
    registry = registry_with("abcxyy", "abxx", "abcd", "abcxx")
    error = failure(registry, "abcx")
    expect(error.suggestions).to eq(%w[abcd abcxx abxx])
    expect(error.message).to eq("Unknown function: abcx. Did you mean abcd, abcxx, abxx?")
    expect(failure(registry_with("abcxyy", "abxx"), "abcx").suggestions).to eq(%w[abxx abcxyy])
  end

  it "suggests a built-in once even after an override" do
    parent = JMESPath::Functions.default
    overridden = parent.with("length", signature: [], override: true) { raise "Callback executed" }
    [parent, overridden].each do |registry|
      error = failure(registry, "lenght")
      expect(error.function_name).to eq("lenght")
      expect(error.suggestions).to eq(["length"])
      expect(error.message).to eq("Unknown function: lenght. Did you mean length?")
    end
  end

  it "retains the original message for empty registries and unrelated names" do
    [JMESPath::Functions.new, JMESPath::Functions.default].each do |registry|
      error = failure(registry, "zzzzzzzz")
      expect(error.suggestions).to eq([])
      expect(error.message).to eq("Unknown function: zzzzzzzz")
    end
  end

  it "rejects incompatible lengths before calculating distance" do
    registry = registry_with("a" * 1000)
    expect(JMESPath::Functions::Suggestions).not_to receive(:distance)
    expect(failure(registry, "abc").suggestions).to eq([])
  end

  it "avoids matching for successful calls" do
    registry = JMESPath::Functions.new.with("identity", signature: [[:any]]) { |value| value }
    expect(JMESPath::Functions::Suggestions).not_to receive(:for)
    expect(registry.call("identity", [42])).to eq(42)
  end
end
