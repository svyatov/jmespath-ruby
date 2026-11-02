# frozen_string_literal: true

RSpec.describe "Non-raising expression search" do
  [nil, false, 42, "Ada", [1], { "items" => [] }].each do |value|
    it "preserves a successful #{value.inspect} result" do
      result = JMESPath.compile("@").try_search(value)
      expect(result).to be_a(JMESPath::SearchResult)
      expect(result).to be_frozen
      expect(result.success?).to be(true)
      expect(result.value).to equal(value)
      expect(result.error).to be_nil
      expect(value).not_to be_frozen if value.is_a?(Array) || value.is_a?(Hash)
    end
  end

  it "accepts positional and keyword evaluation options" do
    expression = JMESPath.compile("length(@)")
    expect(expression.try_search([1], { cache_expressions: false }).value).to eq(1)
    expect(expression.try_search([1], cache_expressions: false).value).to eq(1)
    expect(expression.try_search(4, disable_visit_errors: true).value).to be_nil
    expect(expression.try_search(4, disable_visit_errors: true).success?).to be(true)
  end

  [nil, { unknown: true }, { disable_visit_errors: nil }, { functions: nil },
   { max_depth: 0 }, { cache_expressions: 1 }].each do |options|
    it "rejects #{options.inspect} before input access" do
      input = StringIO.new("{}")
      input.define_singleton_method(:read) { raise "input accessed" }
      expect { JMESPath.compile("@").try_search(input, options) }.to raise_error(ArgumentError)
    end
  end

  it "rejects conflicting options before input access" do
    input = StringIO.new("{}")
    input.define_singleton_method(:read) { raise "input accessed" }
    expect { JMESPath.compile("@").try_search(input, { max_depth: 1 }, max_depth: 2) }
      .to raise_error(ArgumentError)
  end

  it "uses configured defaults and per-call overrides" do
    functions = JMESPath::Functions.default.with("custom", signature: [[:any]]) { |value| [value] }
    expression = JMESPath.compile("custom(@)", functions: functions)
    expect(expression.try_search(7).value).to eq([7])
    replacement = functions.with("custom", signature: [[:any]], override: true) { |value| { value: value } }
    expect(expression.try_search(7, functions: replacement).value).to eq({ value: 7 })
  end

  def search_in_mode(source, data, mode, **options)
    registry = JMESPath::Functions.default.with("identity", signature: [[:any]]) { |value| value }
    expression = JMESPath.compile(source, functions: registry)
    options = options.merge(functions: JMESPath::Functions.default) if mode == :evaluator
    expression.try_search(data, **options)
  end

  %i[compiled evaluator].each do |mode|
    [["length(@)", 4, JMESPath::Errors::InvalidTypeError],
     ["length()", nil, JMESPath::Errors::InvalidArityError],
     ["missing()", {}, JMESPath::Errors::UnknownFunctionError],
     ["sort_by(@, &@)", [1, false], JMESPath::Errors::InvalidTypeError],
     ["contains('abc', @)", 4, JMESPath::Errors::InvalidTypeError],
     ["sum(@)", [Float::INFINITY], JMESPath::Errors::InvalidTypeError]].each do |source, data, klass|
      it "captures #{source} failures through #{mode}" do
        result = search_in_mode(source, data, mode)
        expect(result.success?).to be(false)
        expect(result.value).to be_nil
        expect(result.error).to be_a(klass)
        expect(result).to be_frozen
        expect(result.error).not_to be_frozen
      end
    end

    it "preserves validation metadata through #{mode}" do
      error = search_in_mode("length(@)", 4, mode).error
      expect(error.function_name).to eq("length")
      expect(error.source_range).to eq(0...9)
      expect(error.expected_types).to eq(%i[string array object])
      expect(error.argument_position).to eq(1)
    end

    it "captures cyclic normalization through #{mode}" do
      cycle = []
      cycle << cycle
      expect(search_in_mode("to_string(@)", cycle, mode).error).to be_a(JMESPath::Errors::InvalidValueError)
    end

    it "retains validation suppression through #{mode}" do
      %w[length(@) length()].each do |source|
        result = search_in_mode(source, 4, mode, disable_visit_errors: true)
        expect(result.success?).to be(true)
        expect(result.value).to be_nil
      end
      expect(search_in_mode("missing()", nil, mode, disable_visit_errors: true).success?).to be(false)
    end
  end

  it "captures a per-call nesting limit" do
    result = JMESPath.compile("length(a.b)").try_search({}, max_depth: 1)
    expect(result.success?).to be(false)
    expect(result.error).to be_a(JMESPath::Errors::SyntaxError)
  end

  it "uses configured suppression until a per-call override" do
    expression = JMESPath.compile("length(@)", disable_visit_errors: true)
    expect(expression.try_search(4).success?).to be(true)
    expect(expression.try_search(4, disable_visit_errors: false).success?).to be(false)
  end

  [JMESPath::Errors::InvalidTypeError, JMESPath::Errors::InvalidArityError,
   JMESPath::Errors::UnknownFunctionError, JMESPath::Errors::InvalidValueError,
   JSON::ParserError, JSON::NestingError, ArgumentError].each do |klass|
    [false, true].each do |suppressed|
      it "propagates callback #{klass} with suppression #{suppressed}" do
        error = klass.new("application failure")
        error.set_backtrace(["application.rb:1"])
        calls = 0
        functions = JMESPath::Functions.default.with("explode", signature: []) do
          calls += 1
          raise error
        end
        ["explode()", "map(&explode(), @)"].each do |source|
          expression = JMESPath.compile(source, functions: functions, disable_visit_errors: suppressed)
          expect { expression.try_search([1]) }.to(raise_error do |caught|
            expect(caught).to equal(error)
            expect(caught.backtrace).to eq(["application.rb:1"])
          end)
        end
        expect(calls).to eq(2)
      end
    end

    { to_str: "reverse(@)", to_ary: "length(@)", to_hash: "name" }.each do |method, source|
      it "propagates #{klass} from #{method}" do
        error = klass.new("conversion failure")
        error.set_backtrace(["conversion.rb:1"])
        calls = 0
        adapter = Object.new
        adapter.define_singleton_method(method) do
          calls += 1
          raise error
        end
        expect { JMESPath.compile(source).try_search(adapter) }.to(raise_error do |caught|
          expect(caught).to equal(error)
          expect(caught.backtrace).to eq(["conversion.rb:1"])
        end)
        expect(calls).to eq(1)
      end
    end
  end

  it "preserves conversion nesting errors inside serialization" do
    error = JSON::NestingError.new("application conversion")
    adapter = Object.new
    adapter.define_singleton_method(:to_str) { raise error }
    expect { JMESPath.compile("to_string(@)").try_search(adapter) }
      .to(raise_error { |caught| expect(caught).to equal(error) })
  end

  it "does not repeat or reorder stateful conversions" do
    observations = %i[search try_search].map do |method|
      calls = []
      adapter = Object.new
      adapter.define_singleton_method(:to_ary) do
        calls << :array
        nil
      end
      adapter.define_singleton_method(:to_hash) do
        calls << :object
        nil
      end
      adapter.define_singleton_method(:to_str) do
        calls << :string
        "abc"
      end
      result = JMESPath.compile("length(@)").public_send(method, adapter)
      expect(method == :search ? result : result.value).to eq(3)
      calls
    end
    expect(observations.last).to eq(observations.first)
  end

  it "preserves registry override exceptions and keyword dispatch" do
    error = JMESPath::Errors::InvalidValueError.new("registry")
    calls = []
    functions = Class.new(JMESPath::Functions) do
      define_method(:call) do |name, arguments, **keywords|
        calls << [name, arguments, keywords]
        raise error
      end
    end.new
    expression = JMESPath.compile("custom(@)", functions: functions)
    expect { expression.try_search(4) }.to(raise_error { |caught| expect(caught).to equal(error) })
    expect { JMESPath.compile("custom(@)").try_search(4, functions: functions) }
      .to(raise_error { |caught| expect(caught).to equal(error) })
    expect(calls).to eq([["custom", [4], {}], ["custom", [4], { disable_visit_errors: false }]])
  end

  it "evaluates callback arguments once in order" do
    calls = []
    functions = JMESPath::Functions.default
    functions = functions.with("first", signature: []) do
      calls << :first
      1
    end
    functions = functions.with("second", signature: []) do
      calls << :second
      2
    end
    functions = functions.with("combine", signature: [[:any], [:any]]) do |a, b|
      calls << :combine
      a + b
    end
    expect(JMESPath.compile("combine(first(), second())", functions: functions).try_search(nil).value).to eq(3)
    expect(calls).to eq(%i[first second combine])
  end
end
