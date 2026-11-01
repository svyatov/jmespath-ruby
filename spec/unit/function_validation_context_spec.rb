# frozen_string_literal: true

RSpec.describe "Structured function validation" do
  let(:functions) { JMESPath::Functions.default }

  def failure(name, arguments, registry = functions)
    registry.call(name, arguments)
  rescue JMESPath::Errors::RuntimeError => e
    e
  end

  it "reports the full signature and the rejected argument constraint" do
    error = failure("join", [",", [1, 2]])
    expect(error.function_name).to eq("join")
    expect(error.signature).to eq([[:string], [:array_string]])
    expect(error.variadic?).to be(false)
    expect(error.argument_position).to eq(2)
    expect(error.expected_types).to eq([:array_string])
    expect(error.actual_type).to eq(:array)
    expect(error.validation_stage).to eq(:argument)
    expect(error.source_range).to be_nil
    expect(error.message).to eq("Invalid argument 2 for join: array")
  end

  it "preserves unions and accepts empty typed arrays" do
    expect(failure("length", [nil]).expected_types).to eq(%i[string array object])
    expect(failure("sort", [[1, "x"]]).expected_types).to eq(%i[array_number array_string])
    expect(functions.call("join", [",", []])).to eq("")
    expect(functions.call("sort", [[]])).to eq([])
  end

  it "identifies the actual position of a variadic failure" do
    error = failure("merge", [{}, {}, 3])
    expect(error.argument_position).to eq(3)
    expect(error.signature).to eq([[:object]])
    expect(error.expected_types).to eq([:object])
    expect(error.actual_type).to eq(:number)
    expect(error.variadic?).to be(true)
  end

  [["length", [], 1, 0, false], ["length", [1, 2], 1, 2, false],
   ["merge", [], 1, 0, true]].each do |name, args, expected, actual, variadic|
    it "describes #{name} with #{actual} arguments" do
      error = failure(name, args)
      expect(error.function_name).to eq(name)
      expect(error.expected_arity).to eq(expected)
      expect(error.actual_arity).to eq(actual)
      expect(error.variadic?).to eq(variadic)
      expect(error.source_range).to be_nil
    end
  end

  it "describes zero-argument custom signatures" do
    registry = JMESPath::Functions.new.with("zero", signature: []) { 0 }
    error = failure("zero", [1], registry)
    expect(error.signature).to eq([])
    expect(error.expected_arity).to eq(0)
    expect(error.actual_arity).to eq(1)
  end

  [JMESPath::Errors::InvalidTypeError, JMESPath::Errors::InvalidArityError].each do |klass|
    it "preserves absent metadata and message for #{klass}" do
      error = klass.new("callback")
      fields = %i[function_name signature variadic? source_range]
      fields += if klass == JMESPath::Errors::InvalidTypeError
                  %i[argument_position expected_types actual_type validation_stage]
                else
                  %i[expected_arity actual_arity]
                end
      expect(fields.map { |field| error.public_send(field) }).to all(be_nil)
      expect(error.message).to eq("callback")
    end
  end

  it "owns immutable metadata independent of callers" do
    name = +"join"
    signature = [[:string], [:array_string]]
    types = [:array_string]
    range = (0...9)
    error = JMESPath::Errors::InvalidTypeError.new("bad", function_name: name, signature: signature,
                                                          expected_types: types, source_range: range)
    name.replace("other")
    signature[0] << :number
    types << :number
    expect(error.function_name).to eq("join")
    expect(error.signature).to eq([[:string], [:array_string]])
    expect(error.expected_types).to eq([:array_string])
    expect([error.function_name, error.signature, *error.signature, error.expected_types,
            error.source_range]).to all(be_frozen)
  end

  %w[sort_by min_by max_by].each do |name|
    [[[false], :boolean, %i[number string]], [[1, "x"], :string, [:number]],
     [["x", 1], :number, [:string]]].each do |keys, actual, expected|
      it "describes #{name} expression results #{keys.inspect}" do
        reference = JMESPath::ExpressionReference.new { |item| item }
        error = failure(name, [keys, reference])
        expect(error.function_name).to eq(name)
        expect(error.argument_position).to eq(2)
        expect(error.validation_stage).to eq(:expression_result)
        expect(error.actual_type).to eq(actual)
        expect(error.expected_types).to eq(expected)
        expect(error.signature).to eq([[:array], [:expref]])
        expect(functions.call(name, [[], reference])).to eq(name == "sort_by" ? [] : nil)
      end
    end
  end

  it "describes a built-in constraint narrower than its signature" do
    error = failure("contains", ["abc", 4])
    expect(error.function_name).to eq("contains")
    expect(error.argument_position).to eq(2)
    expect(error.expected_types).to eq([:string])
    expect(error.actual_type).to eq(:number)
    expect(error.validation_stage).to eq(:argument)
    expect(error.signature).to eq([%i[array string], [:any]])
  end

  it "avoids diagnostic conversions when an adapter changes its result" do
    calls = 0
    value = Object.new
    value.define_singleton_method(:to_str) do
      calls += 1
      "abc" if calls == 1
    end
    error = failure("length", [value])
    expect(calls).to eq(2)
    expect(error.function_name).to eq("length")
    expect(error.argument_position).to eq(1)
    expect(error.actual_type).to eq(:unknown)
    expect(error.validation_stage).to eq(:argument)
  end

  it "reports a native rejected boolean without including its value" do
    error = failure("contains", ["abc", false])
    expect(error.actual_type).to eq(:boolean)
    expect(error.argument_position).to eq(2)
    expect(error.expected_types).to eq([:string])
  end

  [JMESPath::Errors::InvalidTypeError, JMESPath::Errors::InvalidArityError].each do |klass|
    it "leaves application #{klass} untouched" do
      original = klass.new("callback failure")
      trace = nil
      registry = functions.with("broken", signature: []) do
        raise original
      rescue klass => e
        trace = e.backtrace.dup
        raise
      end
      [false, true].each do |suppress|
        expect { registry.call("broken", [], disable_visit_errors: suppress) }.to(raise_error do |error|
          expect(error).to equal(original)
          expect(error.backtrace).to eq(trace)
          expect(error.function_name).to be_nil
        end)
      end
    end
  end
end
