# frozen_string_literal: true

RSpec.describe "Non-raising search context" do
  def registry(&block)
    JMESPath::Functions.default.with("custom", signature: [], &block)
  end

  def expect_clean_scope
    expect { JMESPath.compile("length(@)").search(4) }.to raise_error(JMESPath::Errors::InvalidTypeError)
    expect(JMESPath.compile("length(@)").try_search(4).success?).to be(false)
  end

  it "propagates nested ordinary query failures from callbacks and references" do
    observed = nil
    functions = registry do
      JMESPath.search("length(@)", 4)
    rescue JMESPath::Errors::InvalidTypeError => e
      observed = e
      raise
    end
    ["custom()", "map(&custom(), @)"].each do |source|
      expect { JMESPath.compile(source, functions: functions).try_search([1]) }
        .to(raise_error { |caught| expect(caught).to equal(observed) })
      expect_clean_scope
    end
  end

  it "allows callbacks to handle inner failure results" do
    inner = JMESPath.compile("length(@)")
    functions = registry { inner.try_search(4).success? ? "unexpected" : "handled" }
    result = JMESPath.compile("custom()", functions: functions).try_search(nil)
    expect(result.success?).to be(true)
    expect(result.value).to eq("handled")
    expect_clean_scope
  end

  it "propagates errors re-raised from inner and prior failure results" do
    prior = JMESPath.compile("length(@)").try_search(4).error
    [prior, nil].each do |saved|
      error = nil
      functions = registry do
        error = saved || JMESPath.compile("length(@)").try_search(4).error
        raise error
      end
      expect { JMESPath.compile("custom()", functions: functions).try_search(nil) }
        .to(raise_error { |caught| expect(caught).to equal(error) })
      expect_clean_scope
    end
  end

  it "restores capture after callbacks rescue their own failures" do
    functions = registry do
      JMESPath.search("length(@)", 4)
    rescue JMESPath::Errors::InvalidTypeError
      7
    end
    result = JMESPath.compile("reverse(custom())", functions: functions).try_search(nil)
    expect(result.error.function_name).to eq("reverse")
    expect_clean_scope
  end

  it "restores capture after conversions handle inner failure results" do
    adapter = Object.new
    adapter.define_singleton_method(:to_hash) do
      JMESPath.compile("length(@)").try_search(4)
      { "value" => 7 }
    end
    result = JMESPath.compile("reverse(value)").try_search(adapter)
    expect(result.error.function_name).to eq("reverse")
    expect_clean_scope
  end

  it "propagates nested ordinary failures from conversions and registry overrides" do
    observed = nil
    nested = lambda do
      JMESPath.search("length(@)", 4)
    rescue JMESPath::Errors::InvalidTypeError => e
      observed = e
      raise
    end
    adapter = Object.new
    adapter.define_singleton_method(:to_hash, &nested)
    functions = Class.new(JMESPath::Functions) do
      define_method(:call) { |*_arguments| nested.call }
    end.new
    [-> { JMESPath.compile("value").try_search(adapter) },
     -> { JMESPath.compile("custom()", functions: functions).try_search(nil) }].each do |call|
      expect(&call).to(raise_error { |caught| expect(caught).to equal(observed) })
      expect_clean_scope
    end
  end

  it "isolates overlapping calls sharing one expression across threads" do
    ready = Queue.new
    release = Queue.new
    sentinel = JMESPath::Errors::InvalidValueError.new("application")
    functions = JMESPath::Functions.default.with("wait", signature: [[:number]]) do |value|
      ready << true
      release.pop
      raise sentinel if value == 1

      value
    end
    expression = JMESPath.compile("reverse(wait(@))", functions: functions)
    workers = [1, 2].map do |value|
      Thread.new do
        expression.try_search(value)
      rescue JMESPath::Errors::InvalidValueError => e
        e
      end
    end
    2.times { ready.pop }
    2.times { release << true }
    expect(workers.first.value).to equal(sentinel)
    expect(workers.last.value.error.function_name).to eq("reverse")
    expect_clean_scope
  ensure
    workers&.each do |worker|
      worker.kill if worker.alive?
      worker.join
    end
  end

  it "restores independent contexts when fibers alternate through callbacks" do
    functions = registry do
      Fiber.yield :waiting
      JMESPath.compile("length(@)").try_search(4)
      7
    end
    expression = JMESPath.compile("reverse(custom())", functions: functions)
    fibers = Array.new(2) { Fiber.new { expression.try_search(nil) } }
    expect(fibers.map(&:resume)).to eq(%i[waiting waiting])
    results = fibers.reverse.map(&:resume)
    expect(results.map { |result| result.error.function_name }).to eq(%w[reverse reverse])
    expect(results.first.error).not_to equal(results.last.error)
    expect_clean_scope
  end

  it "preserves the actual escaping instance of a frozen exception" do
    frozen = JMESPath::Errors::InvalidValueError.new("frozen")
    frozen.set_backtrace(["application.rb:1"])
    frozen.freeze
    observed = nil
    functions = registry do
      raise frozen
    rescue JMESPath::Errors::InvalidValueError => e
      observed = e
      raise
    end
    expect { JMESPath.compile("custom()", functions: functions).try_search(nil) }
      .to(raise_error { |caught| expect(caught).to equal(observed) })
    expect(frozen).to be_frozen
    expect(frozen.backtrace).to eq(["application.rb:1"])
    expect_clean_scope
  end

  it "uses identity without calling application exception equality or hashing" do
    error = JMESPath::Errors::InvalidValueError.new("identity")
    %i[== eql? hash].each { |method| error.define_singleton_method(method) { |*_args| raise "equality invoked" } }
    functions = registry { raise error }
    2.times do
      expect { JMESPath.compile("custom()", functions: functions).try_search(nil) }
        .to(raise_error { |caught| expect(caught).to equal(error) })
      expect_clean_scope
    end
  end

  it "excludes a previously owned suppressed error when a callback re-raises it" do
    observed = nil
    functions = registry { raise observed }
    tracer = TracePoint.new(:raise) do |event|
      observed ||= event.raised_exception if event.raised_exception.is_a?(JMESPath::Errors::InvalidTypeError)
    end
    expression = JMESPath.compile("[length(@), custom()]", functions: functions, disable_visit_errors: true)
    expect { tracer.enable { expression.try_search(4) } }
      .to(raise_error { |caught| expect(caught).to equal(observed) })
    expect_clean_scope
  ensure
    tracer&.disable
  end

  it "propagates nested query failures from Hash default callbacks" do
    observed = nil
    input = Hash.new do
      JMESPath.search("length(@)", 4)
    rescue JMESPath::Errors::InvalidTypeError => e
      observed = e
      raise
    end
    expect { JMESPath.compile("missing").try_search(input) }
      .to(raise_error { |caught| expect(caught).to equal(observed) })
  end

  %i[to_json to_s].each do |method|
    it "preserves nesting errors raised by serialization #{method}" do
      error = JSON::NestingError.new("application serializer")
      value = Object.new
      value.define_singleton_method(method) { |*_args| raise error }
      expect { JMESPath.compile("to_string(@)").try_search({ value: value }) }
        .to(raise_error { |caught| expect(caught).to equal(error) })
    end
  end

  it "retains custom JSON output and serialization call counts" do
    calls = []
    value = Object.new
    value.define_singleton_method(:to_json) do |state|
      calls << state.class
      "42"
    end
    result = JMESPath.compile("to_string(@)").try_search([value, nil, true, false, "x", 1, 2.5])
    expect(result.value).to eq('[42,null,true,false,"x",1,2.5]')
    expect(calls).to eq([JSON::State])
  end

  it "captures native JSON nesting failures" do
    value = 0
    110.times { value = [value] }
    result = JMESPath.compile("to_string(@)").try_search(value)
    expect(result.error).to be_a(JMESPath::Errors::InvalidValueError)
  end

  it "preserves JSON fallback for objects without to_json" do
    value = Class.new do
      undef_method :to_json

      def to_s
        "fallback"
      end
    end.new
    expect(JMESPath.compile("to_string(@)").try_search(value).value).to eq('"fallback"')
  end

  it "isolates simultaneously active scopes in fibers" do
    fibers = Array.new(2) do
      input = { "value" => 4 }
      paused = false
      input.define_singleton_method(:is_a?) do |type|
        unless paused
          paused = true
          Fiber.yield :active
        end
        super(type)
      end
      Fiber.new { JMESPath.compile("length(value)").try_search(input) }
    end
    expect(fibers.map(&:resume)).to eq(%i[active active])
    expect(fibers.map(&:resume).map { |result| result.error.function_name }).to eq(%w[length length])
    expect_clean_scope
  end

  it "does not inherit capture into new threads or fibers" do
    outcomes = []
    input = { "value" => 4 }
    checked = false
    input.define_singleton_method(:is_a?) do |type|
      unless checked
        checked = true
        ordinary = lambda do
          adapter = Object.new
          adapter.define_singleton_method(:to_str) { raise JSON::NestingError, "application" }
          JMESPath.search("to_string(@)", adapter)
        rescue JMESPath::Errors::InvalidValueError
          :ordinary
        end
        outcomes << Thread.new(&ordinary).value
        outcomes << Fiber.new(&ordinary).resume
      end
      super(type)
    end
    expect(JMESPath.compile("length(value)").try_search(input).success?).to be(false)
    expect(outcomes).to eq(%i[ordinary ordinary])
    expect_clean_scope
  end

  %i[module expression trace function].each do |entry|
    it "propagates nested #{entry} failures from an overridden native value method" do
      observed = nil
      value = "abc".dup
      value.define_singleton_method(:length) do
        case entry
        when :module then JMESPath.search("reverse(@)", 4)
        when :expression then JMESPath.compile("reverse(@)").search(4)
        when :trace then JMESPath.compile("reverse(@)").trace(4)
        when :function then JMESPath::Functions.default.call("reverse", [4])
        end
      rescue JMESPath::Errors::InvalidTypeError => e
        observed = e
        raise
      end
      expect { JMESPath.compile("length(@)").try_search(value) }
        .to(raise_error { |caught| expect(caught).to equal(observed) })
      expect_clean_scope
    end
  end
end
