# frozen_string_literal: true

require_relative "../support/evaluate"
require_relative "../support/wrappers"

RSpec.describe "Projection evaluation" do
  {
    ["items[*].x", { items: [{ x: 1 }, {}, { x: false }] }] => [1, false],
    ["items[?ok].x", { items: [{ ok: true, x: 1 }, { ok: false, x: 2 }] }] => [1],
    ["[]", [[1, 2], [3, [4]]]] => [1, 2, 3, [4]],
    ["[].x", [[{ x: 1 }], [{ x: 2 }], { x: false }]] => [1, 2, false],
    ["*.x", { a: { x: 1 }, b: { x: 2 } }] => [1, 2],
    ["[*].{x:x}", [{}, { x: false }]] => [{ "x" => nil }, { "x" => false }],
    ["[*].x | [0]", [{ x: 1 }, { x: 2 }]] => 1,
    ["[*]", {}] => nil,
    ["[?x]", {}] => nil,
    ["[]", {}] => nil
  }.each do |(query, data), expected|
    it("evaluates #{query} on #{data.inspect}") { expect(evaluate(query, data)).to eq(expected) }
  end

  it "nests object wildcards and filters inside projections" do
    expect(evaluate("*.*", { a: { x: 1 }, b: { y: 2 } })).to eq([[1], [2]])
    expect(evaluate("[*.*]", [])).to eq([nil])
    expect(evaluate("*[?[0] == #{96.chr}0#{96.chr}]", { a: [0, 1], b: [2, 3] })).to eq([[], []])
  end

  it "supports wrappers without converting selected elements" do
    child = Hashish.new("x" => 1)
    expect(evaluate("[*]", Arrayish.new([child]))).to eq([child])
  end

  it "evaluates long field chains without recursive traversal" do
    data = 7
    2_000.times { data = { "a" => data } }
    expect(evaluate(Array.new(2_000, "a").join("."), data)).to eq(7)
  end
end
