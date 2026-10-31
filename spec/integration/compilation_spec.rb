# frozen_string_literal: true

RSpec.describe "Compiled expressions" do
  it "reuses syntax across documents" do
    expression = JMESPath.compile("foo")
    expect(expression.search({ foo: 1 })).to eq(1)
    expect(expression.search({ foo: 2 })).to eq(2)
    expect(expression).to be_frozen
  end

  it "owns its expression text independently of caller mutation" do
    source = +"foo"
    expression = JMESPath.compile(source)
    source.replace("bar")
    expect(expression.search({ foo: 1, bar: 2 })).to eq(1)
    expect(JMESPath.compile(source).search({ foo: 1, bar: 2 })).to eq(2)
  end

  it "isolates mutable literals and function registries across searches" do
    expression = JMESPath.compile("#{96.chr}{\"a\":[1]}#{96.chr}")
    expression.search({})["a"] << 2
    expect(expression.search({})).to eq("a" => [1])
    function = JMESPath.compile("custom()")
    first = JMESPath::Functions.default.with("custom", signature: []) { 1 }
    second = JMESPath::Functions.default.with("custom", signature: []) { 2 }
    expect(function.search({}, functions: first)).to eq(1)
    expect(function.search({}, functions: second)).to eq(2)
  end

  it "can disable shared compilation caching" do
    first = JMESPath.compile("uncached", cache_expressions: false)
    second = JMESPath.compile("uncached", cache_expressions: false)
    expect(first).not_to equal(second)
    expect(second.search({ uncached: 3 }, cache_expressions: false)).to eq(3)
  end

  it "validates per-call nesting limits without reparsing" do
    expression = JMESPath.compile("((@))")
    expect { expression.search({}, max_depth: 1) }.to raise_error(JMESPath::Errors::SyntaxError)
  end
end
