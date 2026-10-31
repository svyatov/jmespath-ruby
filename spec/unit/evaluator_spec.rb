# frozen_string_literal: true

require_relative "../support/evaluate"

RSpec.describe "Expression evaluation" do
  {
    ["foo.bar[-1]", { foo: { bar: [1, 2] } }] => 2,
    ["a || 'fallback'", { a: [] }] => "fallback",
    ["a && unknown()", { a: false }] => false,
    ["{a: missing, b: #{96.chr}false#{96.chr}}", {}] => { "a" => nil, "b" => false },
    ["[x, y]", { x: 1 }] => [1, nil],
    ["(x)", { x: 1 }] => 1,
    ["!x", { x: 0 }] => false,
    ["!x", { x: [] }] => true,
    ["x == y", { x: 1, y: 1.0 }] => true,
    ["x != y", { x: true, y: 1 }] => true,
    ["x < y", { x: "a", y: "b" }] => true,
    ["x >= y", { x: 2, y: 2 }] => true,
    ["x > y", { x: 2, y: "a" }] => nil,
    ["x | y", { x: { y: 4 } }] => 4,
    ["@[8]", [1]] => nil,
    ["missing.foo", {}] => nil,
    ["[x]", nil] => nil
  }.each do |(source, data), expected|
    it("evaluates #{source.inspect} on #{data.inspect}") { expect(evaluate(source, data)).to eq(expected) }
  end

  it "uses a custom registry and preserves short circuiting" do
    registry = JMESPath::Functions.new.with("double", signature: [[:number]]) { |number| number * 2 }
    expect(evaluate("double(x)", { x: 2 }, functions: registry)).to eq(4)
    expect(evaluate("x || unknown()", { x: 1 })).to eq(1)
  end

  it "gives expression references the current evaluator" do
    registry = JMESPath::Functions.new.with("apply", signature: [[:expref], [:any]]) { |ref, value| ref.call(value) }
    expect(evaluate("apply(&name, user)", { user: { name: "Ada" } }, functions: registry)).to eq("Ada")
  end

  it "copies every mutable literal result" do
    node = JMESPath::Parser.new("#{96.chr}{\"a\":[\"value\"]}#{96.chr}").parse
    evaluator = JMESPath::Evaluator.new(functions: JMESPath::Functions.new)
    evaluator.evaluate(node, {})["a"][0].replace("changed")
    expect(evaluator.evaluate(node, {})).to eq("a" => ["value"])
  end
end
