# frozen_string_literal: true

require_relative "../support/evaluate"

RSpec.describe "Collection built-in functions" do
  let(:registry) { JMESPath::Functions.default }

  {
    ["avg", [[1, 2, 3]]] => 2.0,
    ["avg", [[]]] => nil,
    ["sum", [[1, 2, 3]]] => 6,
    ["min", [[3, 1, 2]]] => 1,
    ["max", [%w[a b]]] => "b",
    ["sort", [[3, 1, 2]]] => [1, 2, 3],
    ["join", ["-", %w[a b]]] => "a-b",
    ["keys", [{ "a" => 1, "b" => 2 }]] => %w[a b],
    ["values", [{ "a" => 1, "b" => 2 }]] => [1, 2],
    ["merge", [{ "a" => 1 }, { "a" => 2, "b" => 3 }]] => { "a" => 2, "b" => 3 }
  }.each do |(name, arguments), expected|
    it("evaluates #{name}(#{arguments.inspect})") { expect(registry.call(name, arguments)).to eq(expected) }
  end

  %w[avg sum min max sort join keys values merge map sort_by min_by max_by].each do |name|
    it("checks argument counts for #{name}") do
      expect { registry.call(name, []) }.to raise_error(JMESPath::Errors::InvalidArityError)
    end
  end

  it "preserves null map results" do
    expect(evaluate("map(&x, @)", [{ x: 1 }, {}], functions: registry)).to eq([1, nil])
  end

  it "sorts expression keys stably without replacing objects" do
    data = [{ rank: 1, id: "a" }, { rank: 1, id: "b" }, { rank: 0, id: "c" }]
    result = evaluate("sort_by(@, &rank)", data, functions: registry)
    expect(result).to eq([data[2], data[0], data[1]])
    expect(result[1]).to equal(data[0])
  end

  it "selects minimum and maximum by evaluated keys" do
    data = [{ x: 2 }, { x: 1 }, { x: 3 }]
    expect(evaluate("min_by(@, &x)", data, functions: registry)).to equal(data[1])
    expect(evaluate("max_by(@, &x)", data, functions: registry)).to equal(data[2])
  end

  it "does not evaluate expression keys for empty input" do
    expect(evaluate("min_by(@, &missing)", [], functions: registry)).to be_nil
    expect(evaluate("max_by(@, &missing)", [], functions: registry)).to be_nil
    expect(evaluate("sort_by(@, &missing)", [], functions: registry)).to eq([])
  end

  it "checks every variadic object and every sort key" do
    expect { registry.call("merge", [{}, 1]) }.to raise_error(JMESPath::Errors::InvalidTypeError)
    expect { registry.call("sort", [[1, "x"]]) }.to raise_error(JMESPath::Errors::InvalidTypeError)
    expect { evaluate("sort_by(@, &x)", [{ x: 1 }, { x: "a" }], functions: registry) }
      .to raise_error(JMESPath::Errors::InvalidTypeError)
  end
end
