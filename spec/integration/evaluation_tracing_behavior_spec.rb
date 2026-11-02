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
end
