# frozen_string_literal: true

require "tmpdir"
require_relative "../../script/benchmark"

RSpec.describe "Benchmark evidence" do
  let(:root) { File.expand_path("../..", __dir__) }

  it "reports verified timings, allocations, and isolated interpreter metadata" do
    report = BenchmarkRun.new(ruby_root: root, iterations: 2, rounds: 1, only: "field").run
    expect(report.fetch(:workload_sha256).length).to eq(64)
    expect(report.fetch(:measurements).length).to eq(4)
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
end
