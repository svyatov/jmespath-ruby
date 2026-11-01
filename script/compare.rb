# frozen_string_literal: true

require_relative "benchmark"
require "time"

# Compares published providers without treating rejected queries as timing wins.
class ComparisonRun < BenchmarkRun
  def initialize(implementations:, warmup: 2000, **)
    raise ArgumentError, "warmup must be positive" unless warmup.positive?

    super(ruby_root: implementations.values.first.fetch(:root), **)
    @implementations = implementations
    @warmup = warmup
  end

  def run
    before = fingerprints
    workload = workload_hash
    measurements = collect_measurements
    raise "Benchmark inputs changed during measurement" unless before == fingerprints && workload == workload_hash

    { measured_at: Time.now.utc.iso8601, iterations: @iterations, warmup: @warmup, rounds: @rounds,
      workload_sha256: workload, implementations: @implementations, source_sha256: before,
      measurements: measurements }
  end

  private

  def collect_measurements
    measurements = []
    @rounds.times do |round|
      @implementations.to_a.rotate(round % @implementations.size).each do |name, implementation|
        warn "Round #{round + 1}/#{@rounds}: #{name}"
        measure_provider(name, implementation, measurements, round)
      end
    end
    measurements
  end

  def fingerprints
    @implementations.transform_values do |implementation|
      root = implementation.fetch(:root)
      digest = Digest::SHA256.new
      # MRI and JRuby return nested glob results in different orders.
      paths = Dir[File.join(root, "lib/**/*")].sort # rubocop:disable Lint/RedundantDirGlobSort
      paths.each do |path|
        digest << path.delete_prefix("#{root}/") << File.binread(path) if File.file?(path)
      end
      digest.hexdigest
    end
  end

  def measure_provider(name, implementation, measurements, round)
    worker = ReferenceWorker.new(provider_command(implementation), timeout: 120)
    @queries.rotate(round % @queries.size).each do |query|
      %w[search cached].each do |mode|
        entry = measurement(measurements, name, query.fetch("name"), mode)
        entry[:samples] << request_sample(worker, query, mode)
      end
    end
  ensure
    worker&.close
  end

  def provider_command(implementation)
    [implementation.fetch(:ruby, RbConfig.ruby), "-I", File.join(implementation.fetch(:root), "lib"),
     File.join(ROOT, "script/support/benchmark_worker.rb"), implementation.fetch(:provider)]
  end

  def measurement(measurements, name, workload, mode)
    found = measurements.find { |item| item.values_at(:implementation, :workload, :mode) == [name, workload, mode] }
    return found if found

    entry = { implementation: name, workload: workload, mode: mode, samples: [] }
    measurements << entry
    entry
  end

  def request_sample(worker, query, mode)
    worker.request(payload(query, mode).merge("warmup" => @warmup))
  rescue StandardError => e
    { "error" => "#{e.class}: #{e.message}" }
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  config = output = nil
  OptionParser.new do |parser|
    parser.on("--config PATH") { |value| config = value }
    parser.on("--iterations N", Integer) { |value| options[:iterations] = value }
    parser.on("--warmup N", Integer) { |value| options[:warmup] = value }
    parser.on("--rounds N", Integer) { |value| options[:rounds] = value }
    parser.on("--output PATH") { |value| output = value }
  end.parse!
  implementations = JSON.parse(File.read(config), symbolize_names: true)
  report = JSON.pretty_generate(ComparisonRun.new(implementations: implementations, **options).run)
  File.write(output, "#{report}\n") if output
  puts report unless output
end
