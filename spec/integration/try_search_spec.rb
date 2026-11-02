# frozen_string_literal: true

RSpec.describe "Non-raising expression search" do
  [nil, false, 42, "Ada", [1], { "items" => [] }].each do |value|
    it "preserves a successful #{value.inspect} result" do
      result = JMESPath.compile("@").try_search(value)
      expect(result).to be_a(JMESPath::SearchResult)
      expect(result).to be_frozen
      expect(result.success?).to be(true)
      expect(result.value).to equal(value)
      expect(result.error).to be_nil
      expect(value).not_to be_frozen if value.is_a?(Array) || value.is_a?(Hash)
    end
  end

  it "accepts positional and keyword evaluation options" do
    expression = JMESPath.compile("length(@)")
    expect(expression.try_search([1], { cache_expressions: false }).value).to eq(1)
    expect(expression.try_search([1], cache_expressions: false).value).to eq(1)
    expect(expression.try_search(4, disable_visit_errors: true).value).to be_nil
    expect(expression.try_search(4, disable_visit_errors: true).success?).to be(true)
  end

  [nil, { unknown: true }, { disable_visit_errors: nil }, { functions: nil },
   { max_depth: 0 }, { cache_expressions: 1 }].each do |options|
    it "rejects #{options.inspect} before input access" do
      input = StringIO.new("{}")
      input.define_singleton_method(:read) { raise "input accessed" }
      expect { JMESPath.compile("@").try_search(input, options) }.to raise_error(ArgumentError)
    end
  end

  it "rejects conflicting options before input access" do
    input = StringIO.new("{}")
    input.define_singleton_method(:read) { raise "input accessed" }
    expect { JMESPath.compile("@").try_search(input, { max_depth: 1 }, max_depth: 2) }
      .to raise_error(ArgumentError)
  end

  it "uses configured defaults and per-call overrides" do
    functions = JMESPath::Functions.default.with("custom", signature: [[:any]]) { |value| [value] }
    expression = JMESPath.compile("custom(@)", functions: functions)
    expect(expression.try_search(7).value).to eq([7])
    replacement = functions.with("custom", signature: [[:any]], override: true) { |value| { value: value } }
    expect(expression.try_search(7, functions: replacement).value).to eq({ value: 7 })
  end
end
