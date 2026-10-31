# frozen_string_literal: true

require "json"
require "jmespath"

# Measures one workload inside the selected implementation's process.
module BenchmarkWorker
  def self.call(request)
    operation = operation_for(request)
    expected = request.fetch("expected")
    request.fetch("warmup").times { |index| operation.call(index) }
    verify(operation.call(0), expected) unless request.fetch("warmup").zero?
    measure(operation, expected, request.fetch("iterations"))
  end

  def self.measure(operation, expected, iterations)
    GC.start
    result = nil
    before = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    iterations.times { |index| result = operation.call(index) }
    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    allocations = GC.stat(:total_allocated_objects) - before
    verify(result, expected)
    { seconds: seconds, allocated_objects: allocations, runtime: runtime }
  end

  def self.operation_for(request)
    expression = request.fetch("expression")
    data = request.fetch("given")
    case request.fetch("mode")
    when "compiled"
      compiled_operation(expression, data)
    when "churn"
      churn_operation(expression, data)
    else
      ->(_index) { JMESPath.search(expression, data) }
    end
  end

  def self.churn_operation(expression, data)
    expressions = 320.times.map { |index| (" " * (index + 1)) + expression }
    ->(index) { JMESPath.search(expressions[index % expressions.length], data) }
  end

  def self.compiled_operation(expression, data)
    if JMESPath.respond_to?(:compile)
      compiled = JMESPath.compile(expression)
      ->(_index) { compiled.search(data) }
    else
      compiled = JMESPath::Parser.new.parse(expression).optimize
      ->(_index) { compiled.visit(data) }
    end
  end

  def self.verify(actual, expected)
    raise "Benchmark result mismatch: #{actual.inspect} != #{expected.inspect}" unless actual == expected
  end

  def self.runtime
    { ruby: RUBY_DESCRIPTION, yjit: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?,
      source: $LOADED_FEATURES.find { |path| path.end_with?("/jmespath.rb") } }
  end
end

$stdin.each_line do |line|
  result = begin
    BenchmarkWorker.call(JSON.parse(line))
  rescue StandardError => e
    { error: "#{e.class}: #{e.message}" }
  end
  puts JSON.generate(result)
  $stdout.flush
end
