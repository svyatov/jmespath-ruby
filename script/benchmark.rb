# frozen_string_literal: true

require "json"
require "digest"
require "optparse"
require "rbconfig"
require_relative "support/reference_worker"

# Runs identical, result-checked workloads in isolated implementation processes.
class BenchmarkRun
  ROOT = File.expand_path("..", __dir__)
  MODES = %w[startup search compiled churn].freeze

  def initialize(ruby_root:, iterations: 1000, rounds: 5, queries: nil, only: nil)
    raise ArgumentError, "iterations and rounds must be positive" unless iterations.positive? && rounds.positive?

    @roots = { current: ROOT, reference: File.expand_path(ruby_root) }
    @iterations = iterations
    @rounds = rounds
    @query_path = queries || File.join(ROOT, "benchmark/queries.json")
    @queries = select_queries(only)

    @document_path = File.join(ROOT, "benchmark/documents.json")
    @documents = JSON.parse(File.read(@document_path))
  end

  def run
    measurements = @queries.flat_map do |query|
      MODES.map { |mode| measure(query, mode) }
    end
    { iterations: @iterations, rounds: @rounds, workload_sha256: workload_hash,
      source_sha256: @roots.transform_values { |root| source_hash(root) }, measurements: measurements }
  end

  private

  def select_queries(only)
    queries = JSON.parse(File.read(@query_path))
    queries.select! { |query| query.fetch("name") == only } if only
    raise ArgumentError, "No benchmark workloads selected" if queries.empty?

    queries
  end

  def measure(query, mode)
    samples = @roots.transform_values { [] }
    @rounds.times do |round|
      order = round.even? ? @roots.keys : @roots.keys.reverse
      order.each { |name| samples.fetch(name) << sample(@roots.fetch(name), query, mode) }
    end
    { workload: query.fetch("name"), mode: mode,
      implementations: samples.transform_values { |values| summarize(values) } }
  end

  def sample(root, query, mode)
    command = [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(ROOT, "script/support/benchmark_worker.rb")]
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    worker = ReferenceWorker.new(command)
    result = worker.request(payload(query, mode))
    result["seconds"] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started if mode == "startup"
    raise result.fetch("error") if result.key?("error")

    result
  ensure
    worker&.close
  end

  def payload(query, mode)
    query.merge("given" => @documents.fetch(query.fetch("document")), "mode" => mode,
                "iterations" => mode == "startup" ? 1 : @iterations,
                "warmup" => mode == "startup" ? 0 : 320)
  end

  def summarize(values)
    { seconds: median(values.map { |value| value.fetch("seconds") }),
      allocated_objects: median(values.map { |value| value.fetch("allocated_objects") }),
      runtime: values.first.fetch("runtime"), samples: values }
  end

  def median(values)
    ordered = values.sort
    middle = ordered.length / 2
    ordered.length.odd? ? ordered[middle] : (ordered[middle - 1] + ordered[middle]) / 2.0
  end

  def source_hash(root)
    digest = Digest::SHA256.new
    Dir[File.join(root, "lib/**/*.rb")].each do |path|
      digest << path.delete_prefix("#{root}/") << File.binread(path)
    end
    digest.hexdigest
  end

  def workload_hash
    Digest::SHA256.hexdigest(File.binread(@query_path) + File.binread(@document_path))
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  output = nil
  OptionParser.new do |parser|
    parser.on("--ruby-root PATH") { |value| options[:ruby_root] = value }
    parser.on("--iterations N", Integer) { |value| options[:iterations] = value }
    parser.on("--rounds N", Integer) { |value| options[:rounds] = value }
    parser.on("--only NAME") { |value| options[:only] = value }
    parser.on("--output PATH") { |value| output = value }
  end.parse!
  report = JSON.pretty_generate(BenchmarkRun.new(**options).run)
  File.write(output, "#{report}\n") if output
  puts report
end
