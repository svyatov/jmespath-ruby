# frozen_string_literal: true

require "tmpdir"
require_relative "../../script/benchmark"

RSpec.describe "Benchmark evidence" do
  let(:root) { File.expand_path("../..", __dir__) }

  it "reports verified timings, allocations, and isolated interpreter metadata" do
    report = BenchmarkRun.new(ruby_root: root, iterations: 2, rounds: 1, only: "field").run
    expect(report.fetch(:workload_sha256).length).to eq(64)
    expect(report.fetch(:measurements).map { |entry| entry.fetch(:mode) })
      .to eq(%w[startup search cached compiled churn])
    report.fetch(:measurements).each do |measurement|
      measurement.fetch(:implementations).each_value do |result|
        expect(result.fetch(:seconds)).to be >= 0
        expect(result.fetch(:allocated_objects)).to be > 0
        expect(result.fetch(:samples).length).to eq(1)
        expect(result.fetch(:runtime).fetch("ruby")).to include(RUBY_VERSION)
      end
    end
  end

  it "rejects mismatched expected results" do
    Dir.mktmpdir("jmespath-benchmark") do |directory|
      queries = File.join(directory, "queries.json")
      File.write(queries, JSON.generate([{ name: "broken", expression: "@", document: "items", expected: false }]))
      benchmark = BenchmarkRun.new(ruby_root: root, iterations: 1, rounds: 1, queries: queries)
      expect { benchmark.run }.to raise_error(RuntimeError, /result mismatch/)
    end
  end

  it "includes every case from the four unchanged upstream benchmark files" do
    files = Dir[File.join(root, "benchmark/upstream/*.json")].reject { |path| path.end_with?("sources.json") }
    names = files.flat_map do |path|
      JSON.parse(File.read(path)).flat_map { |group| group.fetch("cases").map { |entry| entry.fetch("name") } }
    end
    expect(files.length).to eq(4)
    expect(names.length).to eq(12)
    selection = BenchmarkRun.new(ruby_root: root, iterations: 1, rounds: 1)
    allow(selection).to receive(:measure) { |query, mode| { workload: query.fetch("name"), mode: mode } }
    measurements = selection.run.fetch(:measurements)
    names.each do |name|
      BenchmarkRun::MODES.each do |mode|
        expect(measurements).to include(workload: name, mode: mode)
      end
    end
    benchmark = BenchmarkRun.new(ruby_root: root, iterations: 1, rounds: 1, only: names.first)
    expect(benchmark.run.fetch(:measurements).map { |entry| entry.fetch(:workload) }).to eq([names.first] * 5)
  end

  it "rejects reports if the implementation changes during measurement" do
    benchmark = BenchmarkRun.new(ruby_root: root, iterations: 1, rounds: 1, only: "field")
    allow(benchmark).to receive(:source_hash).and_return("before", "before", "after", "before")
    expect { benchmark.run }.to raise_error(RuntimeError, /inputs changed/)
  end
end
