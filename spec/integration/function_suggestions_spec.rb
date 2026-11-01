# frozen_string_literal: true

RSpec.describe "Function suggestions during queries" do
  let(:registry_class) do
    Class.new(JMESPath::Functions) do
      def initialize(events)
        @events = events
        super()
      end

      def names
        @events << :names
        super
      end
    end
  end

  def execute(mode, source, functions, suppressed: false)
    if mode == :compiled
      JMESPath.compile(source, functions: functions, disable_visit_errors: suppressed).search(nil)
    else
      node = JMESPath::Parser.new(source).parse
      JMESPath::Evaluator.new(functions: functions, disable_visit_errors: suppressed).evaluate(node, nil)
    end
  end

  def unknown_failure
    yield
  rescue JMESPath::Errors::UnknownFunctionError => e
    e
  end

  %i[compiled interpreted].each do |mode|
    it "inspects names after evaluating arguments in #{mode} execution" do
      events = []
      functions = registry_class.new(events)
                                .with("length", signature: []) { raise "Candidate executed" }
                                .with("first", signature: []) { events << :first }
                                .with("second", signature: []) { events << :second }
      error = unknown_failure { execute(mode, "lenght(first(), second())", functions, suppressed: true) }
      expect(events).to eq(%i[first second names])
      expect(error.suggestions).to eq(["length"])
    end

    it "preserves argument failures before name inspection in #{mode} execution" do
      events = []
      sentinel = RuntimeError.new("argument failure")
      functions = registry_class.new(events)
                                .with("first", signature: []) { raise sentinel }
                                .with("second", signature: []) { events << :second }
      expect { execute(mode, "lenght(first(), second())", functions, suppressed: true) }
        .to(raise_error { |error| expect(error).to equal(sentinel) })
      expect(events).to eq([])
    end

    it "retains custom registry dispatch in #{mode} execution" do
      registry = Class.new(JMESPath::Functions) do
        def call(_name, _arguments, disable_visit_errors: false)
          disable_visit_errors ? 43 : 42
        end

        def names
          raise "Unexpected name inspection"
        end
      end.new
      expect(execute(mode, "lenght(@)", registry)).to eq(42)
      expect(execute(mode, "lenght(@)", registry, suppressed: true)).to eq(43)
    end

    it "preserves callback-owned unknown errors in #{mode} execution" do
      sentinel = JMESPath::Errors::UnknownFunctionError.new("callback failure", function_name: "private_name",
                                                                                suggestions: ["custom"])
      sentinel.set_backtrace(["callback:1"])
      functions = JMESPath::Functions.new.with("explode", signature: []) { raise sentinel }
      error = unknown_failure { execute(mode, "explode()", functions, suppressed: true) }
      expect(error).to equal(sentinel)
      expect(error.message).to eq("callback failure. Did you mean custom?")
      expect(error.function_name).to eq("private_name")
      expect(error.suggestions).to eq(["custom"])
      expect(error.backtrace).to eq(["callback:1"])
    end

    it "suggests only active custom names in #{mode} execution" do
      %w[double dobble].each do |name|
        functions = JMESPath::Functions.new.with(name, signature: [[:any]]) { raise "Candidate executed" }
        error = unknown_failure { execute(mode, "dobule(@)", functions) }
        expect(error.suggestions).to eq([name])
      end
    end
  end

  it "resolves availability during search and respects saved and replacement registries" do
    query = JMESPath.compile("dobule(@)")
    double = JMESPath::Functions.new.with("double", signature: [[:any]]) { nil }
    dobble = JMESPath::Functions.new.with("dobble", signature: [[:any]]) { nil }
    configured = JMESPath.compile("dobule(@)", functions: double)
    expect(unknown_failure { configured.search(nil) }.suggestions).to eq(["double"])
    expect(unknown_failure { configured.search(nil, functions: dobble) }.suggestions).to eq(["dobble"])
    workers = 8.times.map do |index|
      Thread.new do
        registry = index.even? ? double : dobble
        unknown_failure { query.search(nil, functions: registry) }.suggestions
      end
    end
    expect(workers.map(&:value)).to eq([["double"], ["dobble"]] * 4)
    expect(workers.map(&:value)).to all(be_frozen)
    expect(unknown_failure { configured.search(nil) }.suggestions).to eq(["double"])
    expect(unknown_failure { query.search(nil) }.suggestions).to eq([])
  end
end
