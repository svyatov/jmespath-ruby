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

  it "preserves application exception identity and backtraces under suppression" do
    [RuntimeError, JMESPath::Errors::InvalidTypeError, JSON::ParserError].each do |type|
      [false, true].each do |suppressed|
        error = type.new("application failure")
        original_backtrace = nil
        callback = lambda do
          raise error
        rescue type => e
          original_backtrace = e.backtrace.dup
          raise
        end
        functions = JMESPath::Functions.default.with("fail", signature: [], &callback)
        expect { JMESPath.compile("fail()", functions: functions).trace(nil, disable_visit_errors: suppressed) }
          .to(raise_error do |caught|
            expect(caught).to equal(error)
            expect(caught.backtrace).to eq(original_backtrace)
          end)
        adapter = Object.new
        adapter.define_singleton_method(:to_hash, &callback)
        expect { JMESPath.compile("missing").trace(adapter, disable_visit_errors: suppressed) }
          .to(raise_error do |caught|
            expect(caught).to equal(error)
            expect(caught.backtrace).to eq(original_backtrace)
          end)
      end
    end
  end

  it "preserves nested validation ownership and actual suppression" do
    error = nil
    functions = JMESPath::Functions.default.with("nested", signature: []) do
      JMESPath.search("length(@)", 4)
    rescue JMESPath::Errors::InvalidTypeError => e
      error = e
      raise
    end
    expect { JMESPath.compile("map(&nested(), @)", functions: functions).trace([1], disable_visit_errors: true) }
      .to(raise_error { |caught| expect(caught).to equal(error) })
    report = JMESPath.compile("items[*].length(@)", disable_visit_errors: true).trace({ items: [4, "a"] })
    expect(report[:value]).to eq([1])
    expect(report[:events].map { |event| event[:type] }).to eq(["projection_omission"])
  end

  it "matches built-in reference evaluation and input selection identity" do
    data = [{ key: 2 }, { key: 1 }]
    ["sort_by(@, &key)", "min_by(@, &key)", "max_by(@, &key)", "map(&key, @)"].each do |source|
      query = JMESPath.compile(source)
      expect(query.trace(data)[:value]).to eq(query.search(data))
    end
    expect(JMESPath.compile("min_by(@, &key)").trace(data)[:value]).to equal(data.last)
    report = JMESPath.compile("map(&missing, @)").trace(data)
    expect(report[:events].map { |event| event[:context] })
      .to eq([[{ operation_id: 1, index: 0 }], [{ operation_id: 1, index: 1 }]])
  end

  it "preserves conversion counts and calls to overridden built-ins" do
    ["length(@)", "reverse(@)"].each do |source|
      counts = []
      inputs = 2.times.map do
        log = []
        counts << log
        Object.new.tap do |input|
          input.define_singleton_method(:to_str) do
            log << :to_str
            "abc"
          end
        end
      end
      query = JMESPath.compile(source)
      expect(query.trace(inputs.last)[:value]).to eq(query.search(inputs.first))
      expect(counts.last).to eq(counts.first)
      functions = JMESPath::Functions.default.with(source.split("(").first, signature: [[:any]],
                                                                            override: true) do |input|
        input
      end
      expect(query.trace(inputs.first, functions: functions)[:value]).to equal(inputs.first)
    end
  end

  it "preserves keyword omission for custom registry call overrides" do
    type = Class.new(JMESPath::Functions) do
      def call(_name, _arguments)
        7
      end
    end
    functions = type.new
    query = JMESPath.compile("custom()", functions: functions)
    expect(query.search(nil)).to eq(7)
    expect(query.trace(nil)[:value]).to eq(7)
  end

  it "matches compiled and fallback keyword forwarding with registry overrides" do
    type = Class.new(JMESPath::Functions) do
      def call(_name, _arguments, **keywords)
        keywords
      end
    end
    functions = type.new
    ["custom()", "[custom()]", "custom() || @"].each do |source|
      query = JMESPath.compile(source, functions: functions)
      expect(query.trace(nil)[:value]).to eq(query.search(nil))
      expect(query.trace(nil, disable_visit_errors: true)[:value])
        .to eq(query.search(nil, disable_visit_errors: true))
    end
    query = JMESPath.compile("custom()")
    expect(query.trace(nil, functions: functions)[:value]).to eq(query.search(nil, functions: functions))
  end

  it "adds no key predicate or equality callbacks during presence classification" do
    logs = []
    inputs = 2.times.map do
      log = []
      logs << log
      key = Object.new
      key.define_singleton_method(:is_a?) do |type|
        log << type
        false
      end
      key.define_singleton_method(:==) { |_other| raise "extra equality" }
      { key => nil }
    end
    query = JMESPath.compile("x")
    expect(query.trace(inputs.last)[:value]).to eq(query.search(inputs.first))
    expect(logs).to eq([[Symbol], [Symbol]])
  end

  it "classifies identity-based hash lookup conservatively" do
    data = {}.compare_by_identity
    data[+"x"] = nil
    query = JMESPath.compile("x")
    expect(query.search(data)).to be_nil
    expect(query.trace(data)[:events].first[:details][:reason]).to eq("unknown")
  end
end
