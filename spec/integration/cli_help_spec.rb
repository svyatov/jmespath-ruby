# frozen_string_literal: true

require "jmespath/cli"
require "open3"
require "rbconfig"
require "stringio"
require "tmpdir"

RSpec.describe "Command-line topic help" do
  let(:topics) { %w[input output validate functions interactive] }

  def run_cli(arguments, input: double("unused input"), output: StringIO.new)
    errors = StringIO.new
    status = JMESPath::CLI.run(arguments, stdin: input, stdout: output, stderr: errors)
    [status, output.closed? ? "" : output.string, errors.string]
  end

  it "renders every topic without accessing input" do
    expect(File).not_to receive(:open)
    %w[--help -h].each do |flag|
      [nil, *topics].each do |topic|
        arguments = [flag, topic].compact.freeze
        original = arguments.dup
        status, output, errors = run_cli(arguments)
        expect([status, errors]).to eq([0, ""])
        expect(output).not_to be_empty
        expect(arguments).to eq(original)
        expect(output).to include("docs/guides/command-line.md")
        expect(output).to include("https://github.com/svyatov/jmespath-ruby/blob/main/docs/guides/command-line.md")
      end
    end
  end

  it "lists all public options and topic commands in default help" do
    output = run_cli(["--help"])[1]
    %w[-h --help --version --functions --file --query-file --validate --pretty --raw-output
       --json-lines --interactive].each { |option| expect(output).to include(option) }
    topics.each { |topic| expect(output).to include("jmespath --help #{topic}") }
    expect(output).to include("jmespath --file document.json 'user.name'")
    expect(output).not_to include(JMESPath::CLI::FunctionListing::LEGEND, "--*-completion", "--query_file")
  end

  it "keeps examples, restrictions, streams, and statuses in every topic" do
    topics.each do |topic|
      text = run_cli(["--help", topic])[1]
      expect(text).to include("jmespath ", "stdout", "stderr", "status", "0", "1", "2")
    end
    expect(run_cli(%w[--help input])[1]).to include("--file -", "--query-file -", "UTF-8", "-- ends")
    expect(run_cli(%w[--help output])[1]).to include("two-space", "newline", "repeated", "--validate", "Input line N:")
    expect(run_cli(%w[--help validate])[1]).to include("syntax only", "without reading stdin", "--validate --help")
    expect(run_cli(%w[--help functions])[1]).to include(JMESPath::CLI::FunctionListing::LEGEND)
    expect(run_cli(%w[--help interactive])[1]).to include(":help", ":quit", "terminal", "continues")
  end

  it "rejects malformed help before input access" do
    expect(File).not_to receive(:open)
    requests = [["--help=input"], ["-hinput"], %w[@ --help], %w[--file missing --help],
                %w[--query-file missing -h], %w[--interactive --help --file missing]]
    %w[--help -h].each do |flag|
      ["unknown", "", "INPUT", "in", "--help", "-h", "--version", "--functions", "--pretty"].each do |topic|
        requests << [flag, topic]
      end
      requests.push([flag, "input", "output"], [flag, "input", "--file", "missing"],
                    [flag, "--query-file", "missing"], [flag, "--file", "missing"])
    end
    requests.each do |arguments|
      original = arguments.dup
      status, output, errors = run_cli(arguments.freeze)
      expect([status, output]).to eq([2, ""])
      expect(errors).to include("Usage:", "Use jmespath --help")
      expect(arguments).to eq(original)
    end
  end

  it "preserves literal validation before help" do
    expect(File).not_to receive(:open)
    %w[--help -h].each do |literal|
      expect(run_cli(["--validate", literal]))
        .to eq([1, "", "Expected a digit at line 1, column 1\n#{literal}\n^\n"])
    end
  end

  it "preserves help-like filenames and query literals" do
    Dir.mktmpdir("jmespath-help") do |directory|
      Dir.chdir(directory) do
        File.write("--help", '{"name":"Ada"}')
        expect(run_cli(%w[--file=--help name])).to eq([0, "\"Ada\"\n", ""])
        expect(run_cli(["'--help'"], input: StringIO.new("{}"))).to eq([0, "\"--help\"\n", ""])
      end
    end
  end

  it "returns status 1 for help output failures without accessing input" do
    expect(File).not_to receive(:open)
    [nil, *topics].each do |topic|
      output = StringIO.new
      output.close
      expect(run_cli(["--help", topic].compact, output: output).first).to eq(1)
      broken = StringIO.new
      allow(broken).to receive(:puts).and_raise(Errno::EPIPE)
      expect(run_cli(["-h", topic].compact, output: broken).first).to eq(1)
    end
  end

  it "provides identical default and topic behavior through both executables" do
    [nil, *topics, "unknown"].each do |topic|
      %w[--help -h].each do |flag|
        results = %w[jmespath jmespath.rb].map do |name|
          executable = File.expand_path("../../exe/#{name}", __dir__)
          arguments = [flag, topic].compact
          stdout, stderr, status = Open3.capture3(RbConfig.ruby, executable, *arguments, stdin_data: "invalid")
          [status.exitstatus, stdout, stderr]
        end
        expect(results.first).to eq(run_cli([flag, topic].compact))
        expect(results.last).to eq(results.first)
      end
    end
  end
end
