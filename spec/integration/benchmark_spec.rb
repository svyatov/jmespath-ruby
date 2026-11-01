# frozen_string_literal: true

require "tmpdir"
require_relative "../../script/benchmark"
require_relative "../../script/compare"

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

  it "keeps failed workloads out of timing results and continues with valid workloads" do
    Dir.mktmpdir("comparison") do |directory|
      path = File.join(directory, "queries.json")
      queries = [{ name: "wrong", expression: "@", document: "items", expected: false },
                 { name: "valid", expression: "`42`", document: "items", expected: 42 }]
      File.write(path, JSON.generate(queries))
      report = ComparisonRun.new(implementations: { current: { root: root, provider: "jmespath" } },
                                 iterations: 2, warmup: 1, rounds: 1, queries: path).run
      results = report.fetch(:measurements)
      expect(results.length).to eq(4)
      expect(results.select { |entry| entry[:workload] == "wrong" })
        .to all(include(samples: [include("error" => /result mismatch/)]))
      expect(results.select { |entry| entry[:workload] == "valid" })
        .to all(include(samples: [include("seconds" => be >= 0, "runtime" => include("ruby" => RUBY_DESCRIPTION))]))
    end
  end

  it "selects the explicit Jamespath public API in an isolated worker" do
    Dir.mktmpdir("provider") do |directory|
      File.write(File.join(directory, "jamespath.rb"), <<~RUBY)
        module Jamespath
          def self.search(expression, data)
            raise SyntaxError, "unsupported" if expression == "bad"
            data.fetch(expression)
          end
          def self.compile(expression) = Struct.new(:expression) do
            def search(data) = data.fetch(expression)
          end.new(expression)
        end
      RUBY
      worker = ReferenceWorker.new([RbConfig.ruby, "-I", directory,
                                    File.join(root, "script/support/benchmark_worker.rb"), "jamespath"])
      failure = worker.request("expression" => "bad", "given" => {}, "expected" => 42,
                               "mode" => "search", "warmup" => 1, "iterations" => 2)
      expect(failure).to eq("error" => "SyntaxError: unsupported")
      %w[search cached].each do |mode|
        result = worker.request("expression" => "answer", "given" => { "answer" => 42 },
                                "expected" => 42, "mode" => mode, "warmup" => 1, "iterations" => 2)
        expect(result).to include("seconds" => be >= 0)
        expect(result).not_to have_key("error")
      end
    ensure
      worker&.close
    end
  end

  it "reaps a timed-out worker and rejects subsequent requests" do
    worker = ReferenceWorker.new([RbConfig.ruby, "-e", "$stdin.gets; sleep 60"], timeout: 0.1)
    expect { worker.request({}) }.to raise_error(RuntimeError, /timed out/)
    expect { worker.request({}) }.to raise_error(RuntimeError, /unavailable/)
    expect(worker.close).to be_a(String)
  ensure
    worker&.close
  end
end
