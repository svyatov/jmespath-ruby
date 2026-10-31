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

  it "evicts enough entries for a larger expression and retains the most recently used entry" do
    cache = JMESPath::Cache.new(limit: 4, bytes: 4)
    a = JMESPath.compile("a")
    larger = JMESPath.compile("ddd")
    cache.fetch("a", max_depth: 128) { a }
    cache.fetch("b", max_depth: 128) { JMESPath.compile("b") }
    cache.fetch("c", max_depth: 128) { JMESPath.compile("c") }
    cache.fetch("a", max_depth: 128) { raise "lost a before eviction" }
    cache.fetch("ddd", max_depth: 128) { larger }

    expect(cache.fetch("a", max_depth: 128) { raise "evicted newest entry" }).to equal(a)
    expect(cache.fetch("ddd", max_depth: 128) { raise "lost larger entry" }).to equal(larger)
    replacement = JMESPath.compile("b", cache_expressions: false)
    expect(cache.fetch("b", max_depth: 128) { replacement }).to equal(replacement)
  end

  it "can devote the entire byte budget to one expression" do
    cache = JMESPath::Cache.new(limit: 4, bytes: 4)
    cache.fetch("a", max_depth: 128) { JMESPath.compile("a") }
    cache.fetch("b", max_depth: 128) { JMESPath.compile("b") }
    entire = JMESPath.compile("dddd")
    cache.fetch("dddd", max_depth: 128) { entire }

    expect(cache.fetch("dddd", max_depth: 128) { raise "did not cache the full-size entry" }).to equal(entire)
    replacement = JMESPath.compile("a", cache_expressions: false)
    expect(cache.fetch("a", max_depth: 128) { replacement }).to equal(replacement)
  end
end
