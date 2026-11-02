# frozen_string_literal: true

RSpec.describe "Tracing review regressions" do
  it "preserves symbol-fallback objects without additional nil predicates" do
    [true, :raise].each do |behavior|
      value = Object.new
      value.define_singleton_method(:nil?) { behavior == :raise ? raise("extra nil predicate") : true }
      query = JMESPath.compile("x")
      expect(query.search({ x: value })).to equal(value)
      report = query.trace({ x: value })
      expect(report[:value]).to equal(value)
      expect(report[:events]).to eq([])
    end
  end

  it "checks projection omissions by nil identity without application predicates" do
    value = Object.new
    value.define_singleton_method(:nil?) { raise "extra nil predicate" }
    [
      ["[*]", [value]],
      ["items.*", { items: { x: value } }],
      ["items[?'yes']", { items: [value] }]
    ].each do |source, data|
      query = JMESPath.compile(source)
      expect(query.search(data).first).to equal(value)
      report = query.trace(data)
      expect(report[:value].first).to equal(value)
      expect(report[:events]).to eq([])
    end
  end

  it "preserves the original first lookup predicate without claiming explicit null" do
    calls = 0
    value = Object.new
    value.define_singleton_method(:nil?) do
      calls += 1
      true
    end
    report = JMESPath.compile("x").trace({ "x" => value })
    expect(report[:value]).to be_nil
    expect(calls).to eq(1)
    expect(report[:events].first[:details][:reason]).to eq("unknown")
  end

  it "preserves native compiled string strategies without registry callbacks during trace" do
    functions = JMESPath::Functions.default.dup
    calls = []
    functions.define_singleton_method(:call) do |name, _arguments, **_keywords|
      calls << name
      99
    end
    functions.freeze
    ["length(@)", "reverse(@)", "[*].length(@)", "[*].reverse(@)"].each do |source|
      data = source.start_with?("[*]") ? ["abc"] : "abc"
      query = JMESPath.compile(source, functions: functions)
      expect(query.trace(data)[:value]).to eq(query.search(data))
    end
    expect(calls).to eq([])
    query = JMESPath.compile("length(@)", functions: functions)
    expect(query.trace([1, 2])[:value]).to eq(2)
    expect(calls).to eq([])
    expect(query.trace("abc", disable_visit_errors: true)[:value]).to eq(99)
    expect(calls).to eq(["length"])
  end

  it "retains actual compile-time decisions when private definition lookup changes" do
    functions = JMESPath::Functions.default.dup
    definitions = 0
    functions.define_singleton_method(:definition) do |name|
      definitions += 1
      raise "extra resolution" if definitions > 1

      super(name)
    end
    functions.define_singleton_method(:call) { |_name, _arguments, **_keywords| 99 }
    functions.freeze
    query = JMESPath.compile("length(@)", functions: functions)
    expect(definitions).to eq(1)
    expect(query.trace("abc")[:value]).to eq(3)
    expect(definitions).to eq(1)
  end

  it "preserves optimized argument predicate and conversion counts" do
    logs = []
    values = 2.times.map do
      log = []
      logs << log
      Object.new.tap do |value|
        value.define_singleton_method(:is_a?) do |type|
          log << [:is_a, type]
          super(type)
        end
        value.define_singleton_method(:to_str) do
          log << :to_str
          "abc"
        end
      end
    end
    query = JMESPath.compile("length(@)")
    expect(query.trace(values.last)[:value]).to eq(query.search(values.first))
    expect(logs.last).to eq(logs.first)
  end

  it "accepts Struct conversions returning duck mappings with conservative classification" do
    logs = []
    values = 2.times.map do
      log = []
      logs << log
      mapping = Object.new
      mapping.define_singleton_method(:[]) do |key|
        log << [:lookup, key]
        nil
      end
      mapping.define_singleton_method(:each_key) do |&block|
        log << :keys
        block.call(:x)
      end
      Struct.new(:x).new.tap do |value|
        value.define_singleton_method(:to_h) do
          log << :to_h
          mapping
        end
      end
    end
    query = JMESPath.compile("x")
    expect(query.search(values.first)).to be_nil
    report = query.trace(values.last)
    expect(report[:value]).to be_nil
    expect(report[:events].first[:details][:reason]).to eq("unknown")
    expect(logs.last).to eq(logs.first)
  end
end
