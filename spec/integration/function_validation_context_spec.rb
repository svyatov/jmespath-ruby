# frozen_string_literal: true

RSpec.describe "Function validation source context" do
  let(:registry) { JMESPath::Functions.default.with("identity", signature: [[:any]]) { |value| value } }

  def query_failure(source, data, functions, mode)
    expression = mode == :compiled ? JMESPath.compile(source, functions: functions) : JMESPath.compile(source)
    mode == :compiled ? expression.call(data) : expression.call(data, functions: functions)
  rescue JMESPath::Errors::RuntimeError => e
    e
  end

  %i[compiled evaluator].each do |mode|
    it "identifies nested failures through #{mode}" do
      error = query_failure("length(reverse(@))", 4, registry, mode)
      expect(error.function_name).to eq("reverse")
      expect(error.source_range).to eq(7...17)
      expect(error.source_range).to be_frozen
      expect(error.argument_position).to eq(1)
      error = query_failure("map(&length(@), @)", [4], registry, mode)
      expect(error.function_name).to eq("length")
      expect(error.source_range).to eq(5...14)
    end

    it "uses byte ranges through #{mode}" do
      functions = registry.with("length", signature: [[:number]], override: true) { |value| value }
      error = query_failure("'é' | length(@)", nil, functions, mode)
      expect(error.function_name).to eq("length")
      expect(error.source_range).to eq(7...16)
    end

    it "locates result validation and arity failures through #{mode}" do
      error = query_failure("sort_by(@, &key)", [{ key: false }], registry, mode)
      expect(error.source_range).to eq(0...16)
      expect(error.validation_stage).to eq(:expression_result)
      error = query_failure("length()", nil, registry, mode)
      expect(error.source_range).to eq(0...8)
      expect(error.actual_arity).to eq(0)
    end

    it "preserves exact subclass call signatures through #{mode}" do
      functions = Class.new(JMESPath::Functions) do
        def call(_name, _arguments, disable_visit_errors: false)
          disable_visit_errors ? 43 : 42
        end
      end.new
      expect(query_failure("length(@)", "abc", functions, mode)).to eq(42)
      expect(JMESPath.compile("length(@)", functions: functions, disable_visit_errors: true).call("abc")).to eq(43)
    end

    it "preserves callback error identity, context, and backtrace through #{mode}" do
      original = nil
      trace = nil
      functions = registry.with("nested", signature: []) do
        JMESPath.search("reverse(@)", 4)
      rescue JMESPath::Errors::InvalidTypeError => e
        original = e
        trace = e.backtrace.dup
        raise
      end
      error = query_failure("map(&nested(), @)", [1], functions, mode)
      expect(error).to equal(original)
      expect(error.backtrace).to eq(trace)
      expect(error.function_name).to eq("reverse")
      expect(error.source_range).to eq(0...10)
    end
  end

  [["length(@)", 0...9, 3], ["reverse(@)", 0...10, "cba"]].each do |source, range, result|
    it "preserves optimized success and contextual fallback for #{source}" do
      expression = JMESPath.compile(source)
      expect(expression.call("abc")).to eq(result)
      expect { expression.call(4) }.to(raise_error do |error|
        expect(error.source_range).to eq(range)
      end)
    end
  end

  it "isolates concurrent diagnostic context and suppression" do
    ready = Queue.new
    release = Queue.new
    functions = registry.with("wait", signature: [[:number]]) do |value|
      ready << true
      release.pop
      value
    end
    queries = [JMESPath.compile("reverse(wait(@))", functions: functions),
               JMESPath.compile("length(wait(@))", functions: functions)]
    workers = queries.map do |query|
      Thread.new do
        query.call(4)
      rescue JMESPath::Errors::InvalidTypeError => e
        e
      end
    end
    2.times { ready.pop }
    expect(JMESPath.search("length(@)", 4, functions: functions, disable_visit_errors: true)).to be_nil
    2.times { release << true }
    errors = workers.map(&:value)
    expect(errors.map(&:function_name)).to eq(%w[reverse length])
    expect(errors.map(&:source_range)).to eq([0...16, 0...15])
    expect(errors.map(&:signature)).to eq([[%i[string array]], [%i[string array object]]])
    expect(JMESPath.search("map(&length(@), @)", [4], disable_visit_errors: true)).to eq([nil])
  ensure
    workers&.each do |worker|
      worker.kill if worker.alive?
      worker.join
    end
  end
end
