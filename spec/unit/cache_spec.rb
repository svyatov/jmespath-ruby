# frozen_string_literal: true

RSpec.describe "Bounded compilation caching" do
  it "evicts the least recently used entry" do
    cache = JMESPath::Cache.new(limit: 2, bytes: 100)
    calls = 0
    compile = lambda {
      calls += 1
      JMESPath::Expression.new("a", JMESPath::Parser.new("a").parse)
    }
    cache.fetch("a", max_depth: 128, &compile)
    cache.fetch("b", max_depth: 128, &compile)
    cache.fetch("a", max_depth: 128, &compile)
    cache.fetch("c", max_depth: 128, &compile)
    cache.fetch("b", max_depth: 128, &compile)
    expect(calls).to eq(4)
  end

  it "bounds source bytes and bypasses oversized entries" do
    cache = JMESPath::Cache.new(limit: 10, bytes: 2)
    calls = 0
    compile = lambda {
      calls += 1
      JMESPath::Expression.new("a", JMESPath::Parser.new("a").parse)
    }
    2.times { cache.fetch("long", max_depth: 128, &compile) }
    cache.fetch("a", max_depth: 128, &compile)
    cache.fetch("bb", max_depth: 128, &compile)
    cache.fetch("a", max_depth: 128, &compile)
    expect(calls).to eq(5)
  end
end
