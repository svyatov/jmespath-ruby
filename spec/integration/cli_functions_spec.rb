# frozen_string_literal: true

require "open3"
require "rbconfig"
require "stringio"
require "timeout"
require "tmpdir"
require "jmespath/cli"

RSpec.describe "Command-line function listing" do
  def run_cli(arguments, input: double("unused stdin"), output: StringIO.new)
    errors = StringIO.new
    status = JMESPath::CLI.run(arguments, stdin: input, stdout: output, stderr: errors)
    [status, output.string, errors.string]
  end

  def legend
    "Types: any accepts any value; A|B accepts either type.\n" \
      "array<T> requires every element to have type T; array is unrestricted.\n" \
      "expref is an expression reference, written &expression.\n" \
      "T... requires one or more arguments of type T.\n" \
      "Signatures describe declared argument types; runtime checks can be narrower.\n"
  end

  def usage
    "Usage: jmespath [--pretty | --raw-output | --json-lines] [--file PATH] " \
      "(EXPRESSION | --query-file PATH)\n       " \
      "jmespath --validate (EXPRESSION | --query-file PATH)\n       jmespath --functions\n"
  end

  it "lists every built-in once in metadata order without input access or evaluation" do
    input = StringIO.new
    output = StringIO.new
    allow(input).to receive(:read).and_raise("unexpected read")
    allow(input).to receive(:gets).and_raise("unexpected gets")
    allow(File).to receive(:open).and_raise("unexpected file access")
    %i[search compile].each { |method| allow(JMESPath).to receive(method).and_raise("unexpected query") }
    registry = JMESPath::Functions.default
    arguments = ["--functions"].freeze
    status, text, errors = run_cli(arguments, input: input, output: output)
    expect([status, errors]).to eq([0, ""])
    entries, actual_legend = text.split("\n\n", 2)
    expect(actual_legend).to eq(legend)
    lines = entries.lines(chomp: true)
    expect(lines.map { |line| line.split("(", 2).first }).to eq(registry.names)
    registry.names.zip(lines).each do |name, line|
      metadata = registry.metadata(name)
      expect(line).to end_with(") #{metadata.description}")
      parameters = metadata.signature.map do |types|
        types.map { |type| { array_string: "array<string>", array_number: "array<number>" }.fetch(type, type.to_s) }
             .join("|")
      end
      parameters[-1] += "..." if metadata.variadic?
      expect(line).to start_with("#{name}(#{parameters.join(', ')}) ")
    end
    expect(lines).to include(
      "abs(number) Absolute value.",
      "join(string, array<string>) Join strings with a separator.",
      "length(string|array|object) Character or element count.",
      "map(expref, array) Map an expression over an array, including null results.",
      "merge(object...) Merge objects, with later values winning.",
      "sort(array<number>|array<string>) Stable sorted array of numbers or strings."
    )
    expect(input).not_to be_closed
    expect(output).not_to be_closed
    expect(arguments).to eq(["--functions"])
  end

  it "rejects conflicts and malformed listing flags before any input access" do
    allow(File).to receive(:open).and_raise("unexpected file access")
    [%w[--functions --functions], %w[--functions=true], %w[--function], %w[-F],
     %w[--functions @], %w[@ --functions], %w[--functions --],
     %w[--functions --validate], %w[--functions --validate --query-file missing],
     %w[--validate --query-file missing --functions]].each do |arguments|
      expect(run_cli(arguments.freeze)).to eq([2, "", usage])
    end
    [%w[--file missing], %w[--file=missing], %w[--query-file missing], %w[--query-file=missing],
     %w[--pretty], %w[--raw-output], %w[--json-lines], %w[--help], %w[-h], %w[--version]].each do |flags|
      [["--functions", *flags], [*flags, "--functions"]].each do |arguments|
        original = arguments.dup
        expect(run_cli(arguments.freeze)).to eq([2, "", usage])
        expect(arguments).to eq(original)
      end
    end
  end

  it "preserves literal validation and delimiter behavior" do
    diagnostic = "Expected a digit at line 1, column 1\n--functions\n^\n"
    expect(run_cli(%w[--validate --functions])).to eq([1, "", diagnostic])
    expect(run_cli(%w[-- --functions], input: StringIO.new("{}"))).to eq([1, "", diagnostic])
    expect(run_cli(["--", '"--functions"'], input: StringIO.new('{"--functions":7}'))).to eq([0, "7\n", ""])
  end

  it "preserves flag-looking query and document filenames" do
    Dir.mktmpdir("jmespath-functions") do |directory|
      Dir.chdir(directory) do
        File.write("--functions", '{"value":7}')
        [%w[--file --functions value], %w[--file=--functions value]].each do |arguments|
          expect(run_cli(arguments)).to eq([0, "7\n", ""])
        end
        File.write("--functions", "value")
        [%w[--query-file --functions], %w[--query-file=--functions]].each do |arguments|
          expect(run_cli(arguments, input: StringIO.new('{"value":7}'))).to eq([0, "7\n", ""])
        end
      end
    end
  end

  it "reports output failures and propagates unrelated exceptions" do
    output = StringIO.new
    allow(output).to receive(:puts).and_raise(IOError, "write failed")
    expect(run_cli(["--functions"], output: output)).to eq([1, "", "write failed\n"])
    failure = RuntimeError.new("Application failure")
    allow(output).to receive(:puts).and_raise(failure)
    expect { run_cli(["--functions"], output: output) }.to(raise_error { |error| expect(error).to equal(failure) })
    expect(output).not_to be_closed
  end

  it "explains listing in help and preserves standalone information modes" do
    %w[--help -h].each do |flag|
      status, output, errors = run_cli([flag])
      expect([status, errors]).to eq([0, ""])
      expect(output).to start_with(usage)
      expect(output).to include("standalone --functions", "without reading stdin", legend)
    end
    expect(run_cli(["--version"])).to eq([0, "jmespath-ruby #{JMESPath::VERSION}\n", ""])
  end

  %w[jmespath jmespath.rb].each do |name|
    [[%w[--functions], 0], [%w[--functions --query-file missing], 2]].each do |arguments, expected_status|
      it "finishes #{arguments.inspect} through #{name} while stdin remains open" do
        executable = File.expand_path("../../exe/#{name}", __dir__)
        Open3.popen3(RbConfig.ruby, executable, *arguments) do |input, output, errors, waiter|
          status = Timeout.timeout(5) { waiter.value }
          expect(input).not_to be_closed
          expected = expected_status.zero? ? JMESPath::CLI::FunctionListing.render(JMESPath::Functions.default) : ""
          expect([status.exitstatus, output.read, errors.read])
            .to eq([expected_status, expected, expected_status.zero? ? "" : usage])
        ensure
          if waiter.alive?
            Process.kill("KILL", waiter.pid)
            waiter.value
          end
        end
      end
    end
  end
end
