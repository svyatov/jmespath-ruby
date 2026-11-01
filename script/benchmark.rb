# frozen_string_literal: true

require "json"
require "digest"
require "optparse"
require "rbconfig"
require_relative "support/reference_worker"

# Runs identical, result-checked workloads in isolated implementation processes.
class BenchmarkRun
  ROOT = File.expand_path("..", __dir__)
  MODES = %w[startup search cached compiled churn].freeze

  def initialize(ruby_root:, iterations: 1000, rounds: 5, queries: nil, **options)
    raise ArgumentError, "iterations and rounds must be positive" unless iterations.positive? && rounds.positive?

    validate_options(options)

    @roots = { current: ROOT, reference: File.expand_path(ruby_root) }
    @iterations = iterations
    @rounds = rounds
    @memory = options.fetch(:memory, false)
    @query_path = queries || File.join(ROOT, "benchmark/queries.json")
    @queries = select_queries(options[:only])

    @document_path = File.join(ROOT, "benchmark/documents.json")
    @documents = JSON.parse(File.read(@document_path))
  end

  def run
    sources = @roots.transform_values { |root| source_hash(root) }
    workload = workload_hash
    measurements = @queries.flat_map do |query|
      MODES.map { |mode| measure(query, mode) }
    end
    current_sources = @roots.transform_values { |root| source_hash(root) }
    raise "Benchmark inputs changed during measurement" unless sources == current_sources && workload == workload_hash

    { iterations: @iterations, rounds: @rounds, workload_sha256: workload,
      source_sha256: sources, measurements: measurements }
  end

  private

  def validate_options(options)
    raise ArgumentError, "Unknown benchmark options" unless (options.keys - %i[only memory]).empty?
  end

  def select_queries(only)
    queries = JSON.parse(File.read(@query_path))
    queries.concat(upstream_queries) if @query_path == File.join(ROOT, "benchmark/queries.json")
    queries.select! { |query| query.fetch("name") == only } if only
    raise ArgumentError, "No benchmark workloads selected" if queries.empty?

    queries
  end

  def upstream_queries
    upstream_paths.flat_map do |path|
      JSON.parse(File.read(path)).flat_map do |group|
        group.fetch("cases").map do |entry|
          entry.merge("given" => group.fetch("given"), "expected" => entry.fetch("result"))
        end
      end
    end
  end

  def upstream_paths
    Dir[File.join(ROOT, "benchmark/upstream/*.json")].reject { |path| path.end_with?("sources.json") }.sort
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
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    worker = ReferenceWorker.new(command_for(root))
    result = worker.request(payload(query, mode))
    result["seconds"] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started if mode == "startup"
    raise result.fetch("error") if result.key?("error")

    result["peak_rss_bytes"] = peak_memory(worker) if @memory

    result
  ensure
    worker&.close
  end

  def command_for(root)
    command = [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(ROOT, "script/support/benchmark_worker.rb")]
    command.unshift("/usr/bin/time", "-l") if @memory
    command
  end

  def peak_memory(worker)
    diagnostics = worker.close
    Integer(diagnostics[/^\s*(\d+)\s+maximum resident set size/, 1])
  end

  def payload(query, mode)
    data = query.fetch("given") { @documents.fetch(query.fetch("document")) }
    query.merge("given" => data, "mode" => mode,
                "memory" => @memory,
                "iterations" => mode == "startup" ? 1 : @iterations,
                "warmup" => mode == "startup" ? 0 : 320)
  end

  def summarize(values)
    summary = { runtime: values.first.fetch("runtime"), samples: values }
    %w[seconds allocated_objects retained_bytes rss_bytes peak_rss_bytes].each do |metric|
      summary[metric.to_sym] = median(values.map { |value| value.fetch(metric) }) if values.first.key?(metric)
    end
    summary
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
    paths = [@query_path, @document_path, *upstream_paths]
    Digest::SHA256.hexdigest(paths.map { |path| File.binread(path) }.join)
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
    parser.on("--memory", "Measure retained Ruby objects and process RAM (macOS)") { options[:memory] = true }
    parser.on("--output PATH") { |value| output = value }
  end.parse!
  report = JSON.pretty_generate(BenchmarkRun.new(**options).run)
  File.write(output, "#{report}\n") if output
  puts report
end
