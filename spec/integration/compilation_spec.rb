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

  it "parses the same snapshot that identifies a cache entry" do
    source = +"snapshot_before"
    cache = JMESPath.const_get(:CACHE)
    allow(cache).to receive(:fetch).and_wrap_original do |fetch, text, **options, &build|
      fetch.call(text, **options) do |snapshot|
        source.replace("snapshot_after")
        build.call(snapshot)
      end
    end

    expression = JMESPath.compile(source)
    expect(expression.source).to eq("snapshot_before")
    expect(JMESPath.search("snapshot_before", { snapshot_before: 1, snapshot_after: 2 })).to eq(1)
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

  it "evaluates a function argument once before applying native or adapted values" do
    expression = JMESPath.compile("length(text)")
    ["abc", [1, 2, 3]].each do |value|
      reads = 0
      data = Hash.new do
        reads += 1
        value
      end
      expect(expression.search(data)).to eq(3)
      expect(reads).to eq(1)
    end
  end

  it "honors function overrides and suppressed errors after a default search" do
    expression = JMESPath.compile("length(text)")
    functions = JMESPath::Functions.default.with("length", signature: [[:string]], override: true) { 9 }
    expect(expression.search({ "text" => "abc" })).to eq(3)
    expect(expression.search({ "text" => "abc" }, functions: functions)).to eq(9)
    expect(expression.search({ "text" => 4 }, disable_visit_errors: true)).to be_nil
  end

  it "loads stream inputs and evaluates array inputs through compiled syntax" do
    expect(JMESPath.compile("name").search(StringIO.new('{"name":"Ada"}'))).to eq("Ada")
    expect(JMESPath.compile("[0]").search([7, 8])).to eq(7)
  end

  it "evaluates built-in arguments once in source order" do
    reads = []
    data = Hash.new do |_, key|
      reads << key
      key == "first" ? "abc" : "b"
    end
    expect(JMESPath.compile("contains(first, second)").search(data)).to be(true)
    expect(reads).to eq(%w[first second])
  end

  it "returns independent expression references that evaluate their own input" do
    expression = JMESPath.compile("&value")
    first = expression.search(nil)
    second = expression.search(nil)
    expect(first).not_to equal(second)
    expect(first.call({ "value" => 7 })).to eq(7)
    expect(second.call({ "value" => 8 })).to eq(8)
  end
end
