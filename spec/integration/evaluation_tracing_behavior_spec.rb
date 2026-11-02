# frozen_string_literal: true

RSpec.describe "Tracing behavior parity" do
  def lookup_input(log)
    type = Class.new(Hash) do
      define_method(:[]) do |key|
        log << [:lookup, key]
        super(key)
      end
      define_method(:each_key) do |&block|
        log << :keys
        super(&block)
      end
      define_method(:key?) { |_key| raise "extra lookup" }
      define_method(:method) { |_key| raise "extra callback" }
    end
    type.new { |_hash, key| log << [:default, key] }.merge("x" => nil, x: nil)
  end

  it "preserves custom hash accesses and reports uncertain presence conservatively" do
    query = JMESPath.compile("x")
    ordinary_log = []
    traced_log = []
    expect(query.search(lookup_input(ordinary_log))).to be_nil
    report = query.trace(lookup_input(traced_log))
    expect(traced_log).to eq(ordinary_log)
    expect(report[:events].first[:details][:reason]).to eq("unknown")
  end

  it "converts adapters and structs only once per field access" do
    %i[to_hash to_h].each do |conversion|
      counts = []
      values = 2.times.map do
        calls = []
        counts << calls
        input = conversion == :to_h ? Struct.new(:x).new(nil) : Object.new
        input.define_singleton_method(conversion) do
          calls << conversion
          { "x" => nil }
        end
        input
      end
      query = JMESPath.compile("x")
      expect(query.trace(values.last)[:value]).to eq(query.search(values.first))
      expect(counts).to eq([[conversion], [conversion]])
    end
  end

  it "preserves nil adapter conversions and conversion failures" do
    adapter = Object.new
    calls = 0
    adapter.define_singleton_method(:to_hash) do
      calls += 1
      nil
    end
    expect(JMESPath.compile("x").trace(adapter)[:events].first[:details][:reason]).to eq("non_object")
    expect(calls).to eq(1)
    adapter.define_singleton_method(:to_hash) { 7 }
    expect { JMESPath.compile("x").trace(adapter) }.to raise_error(TypeError)
  end

  it "preserves a customized key enumeration with native indexing" do
    hash = { "other" => nil }
    hash.define_singleton_method(:each_key) { |&block| super(&block) }
    expect(JMESPath.compile("x").trace(hash)[:events].first[:details][:reason]).to eq("unknown")
  end

  it "finishes filter conditions before projections even after truncation" do
    log = []
    functions = JMESPath::Functions.default.with("keep", signature: [[:any]]) do |value|
      log << [:keep, value]
      value != 2
    end
    functions = functions.with("emit", signature: [[:any]]) do |value|
      log << [:emit, value]
      value == 1 ? nil : false
    end
    query = JMESPath.compile("items[?keep(@)].emit(@)", functions: functions)
    report = query.trace({ items: [1, 2, 3] }, limit: 1)
    expect(report[:value]).to eq([false])
    expect(log).to eq([[:keep, 1], [:keep, 2], [:keep, 3], [:emit, 1], [:emit, 3]])
    expect(report[:events].length).to eq(1)
    expect(report[:events].first[:type]).to eq("filter_exclusion")
    expect(report[:truncated]).to be(true)
  end

  it "keeps short-circuited callbacks and their diagnostics unvisited" do
    functions = JMESPath::Functions.default.with("bomb", signature: []) { raise "visited" }
    ["x || bomb()", "x && bomb()"].zip([true, false]).each do |source, input|
      report = JMESPath.compile(source, functions: functions).trace({ x: input })
      expect(report).to eq(value: input, events: [], truncated: false)
    end
  end
end
