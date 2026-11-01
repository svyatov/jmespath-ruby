# frozen_string_literal: true

require "json"
provider = ARGV.fetch(0, "jmespath")
require "jruby" if provider == "jmespath-jruby"
require(provider == "jamespath" ? "jamespath" : "jmespath")

# Measures one workload inside the selected implementation's process.
module BenchmarkWorker
  PROVIDER = ARGV.fetch(0, "jmespath")
  ERRORS = [StandardError, SyntaxError].tap do |errors|
    errors << Java::JavaLang::LinkageError if defined?(JRUBY_VERSION)
  end.freeze

  def self.call(request)
    require "objspace" if request["memory"]
    operation = operation_for(request)
    expected = request.fetch("expected")
    warm(operation, expected, request.fetch("warmup"))
    result = measure(operation, expected, request.fetch("iterations"))
    memory_usage(result) if request["memory"]
    result
  end

  def self.warm(operation, expected, iterations)
    return if iterations.zero?

    verify(operation.call(0), expected)
    iterations.times { |index| operation.call(index) }
    verify(operation.call(0), expected)
  end

  def self.memory_usage(result)
    GC.start
    result[:retained_bytes] = ObjectSpace.memsize_of_all
    result[:rss_bytes] = Integer(IO.popen(["ps", "-o", "rss=", "-p", Process.pid.to_s], &:read)) * 1024
  end

  def self.measure(operation, expected, iterations)
    GC.start
    result = nil
    before = allocation_count
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    iterations.times { |index| result = operation.call(index) }
    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    allocations = allocation_count - before if before
    verify(result, expected)
    { seconds: seconds, allocated_objects: allocations, runtime: runtime }
  end

  def self.allocation_count
    GC.stat(:total_allocated_objects) unless defined?(JRUBY_VERSION)
  end

  def self.operation_for(request)
    expression = request.fetch("expression")
    data = request.fetch("given")
    return alternate_operation(request, expression, data) if %w[jamespath jmespath-jruby].include?(PROVIDER)

    case request.fetch("mode")
    when "cached"
      cached_operation(expression, data)
    when "compiled"
      compiled_operation(expression, data)
    when "churn"
      churn_operation(expression, data)
    else
      ->(_index) { JMESPath.search(expression, data) }
    end
  end

  def self.alternate_operation(request, expression, data)
    if PROVIDER == "jamespath"
      query = request.fetch("mode") == "cached" ? Jamespath.compile(expression) : nil
      return ->(_index) { query ? query.search(data) : Jamespath.search(expression, data) }
    end
    runtime = JmesPath.new
    query = request.fetch("mode") == "cached" ? runtime.compile(expression) : nil
    ->(_index) { (query || runtime.compile(expression)).search(data) }
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

  def self.cached_operation(expression, data)
    return compiled_operation(expression, data) if JMESPath.respond_to?(:compile)

    runtime = JMESPath::Runtime.new(cache_expressions: true)
    ->(_index) { runtime.search(expression, data) }
  end

  def self.verify(actual, expected)
    raise "Benchmark result mismatch: #{actual.inspect} != #{expected.inspect}" unless actual == expected
  end

  def self.runtime
    { ruby: RUBY_DESCRIPTION, yjit: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?,
      source: $LOADED_FEATURES.find { |path| path.end_with?("/jmespath.rb", "/jamespath.rb") } }
  end
end

$stdin.each_line do |line|
  result = begin
    BenchmarkWorker.call(JSON.parse(line))
  rescue *BenchmarkWorker::ERRORS => e
    { error: "#{e.class}: #{e.message}" }
  end
  puts JSON.generate(result)
  $stdout.flush
end
