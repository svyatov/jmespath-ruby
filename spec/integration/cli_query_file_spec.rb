# frozen_string_literal: true

require "open3"
require "rbconfig"
require "stringio"
require "timeout"
require "tmpdir"
require "jmespath/cli"

RSpec.describe "Command-line query files" do
  around do |example|
    Dir.mktmpdir("jmespath-query") do |directory|
      @directory = directory
      example.run
    end
  end

  let(:query_path) { File.join(@directory, "query.jmespath") }
  let(:document_path) { File.join(@directory, "document.json") }
  let(:document) { '{"user":{"name":"café"}}' }

  before do
    File.binwrite(query_path, "user.name\n")
    File.write(document_path, document)
  end

  def run_cli(arguments, input: double("unused stdin"))
    output = StringIO.new.set_encoding(Encoding::UTF_8)
    errors = StringIO.new.set_encoding(Encoding::UTF_8)
    status = JMESPath::CLI.run(arguments, stdin: input, stdout: output, stderr: errors)
    [status, output.string, errors.string]
  end

  def usage
    "Usage: jmespath [--file PATH] (EXPRESSION | --query-file PATH)\n       " \
      "jmespath --validate (EXPRESSION | --query-file PATH)\n"
  end

  it "reads query files with stdin or either document option order" do
    expect(run_cli(["--query-file", query_path], input: StringIO.new(document))).to eq([0, "\"café\"\n", ""])
    [["--query-file", query_path, "--file", document_path],
     ["--file", document_path, "--query-file", query_path],
     ["--query-file=#{query_path}", "--file=#{document_path}", "--"]].each do |arguments|
      original = arguments.dup
      expect(run_cli(arguments.freeze)).to eq([0, "\"café\"\n", ""])
      expect(arguments).to eq(original)
    end
  end

  it "preserves trailing options under POSIXLY_CORRECT" do
    previous = ENV.fetch("POSIXLY_CORRECT", nil)
    ENV["POSIXLY_CORRECT"] = "1"
    expect(run_cli(["--query-file", query_path, "--validate"].freeze)).to eq([0, "", ""])
  ensure
    ENV["POSIXLY_CORRECT"] = previous
  end

  it "supports literal spaces, option-like filenames, and minus" do
    ["my query.jmespath", "--query.jmespath", "-"].each do |name|
      File.binwrite(File.join(@directory, name), "user.name\n")
      Dir.chdir(@directory) do
        ["--query-file=#{name}", "--query-file=./#{name}"].each do |option|
          expect(run_cli([option, "--file", document_path])).to eq([0, "\"café\"\n", ""])
        end
      end
    end
    Dir.chdir(@directory) do
      expect(run_cli(["--query-file", "-", "--file", document_path])).to eq([0, "\"café\"\n", ""])
    end
  end

  it "validates either option order without document input" do
    %w[unknown() length()].each do |source|
      File.binwrite(query_path, source)
      expect(run_cli(["--validate", "--query-file", query_path])).to eq([0, "", ""])
      expect(run_cli(["--query-file", query_path, "--validate"])).to eq([0, "", ""])
    end
  end

  it "preserves two-argument validation of flag-like expressions" do
    %w[--help --query-file].each do |source|
      expect(run_cli(["--validate", source]))
        .to eq([1, "", "Expected a digit at line 1, column 1\n#{source}\n^\n"])
    end
  end

  it "rejects invalid combinations before accessing files or stdin" do
    allow(File).to receive(:open).and_raise("unexpected file access")
    [[], ["--query-file"], ["--query-file", query_path, "@"],
     ["--query-file", query_path, "--query-file", query_path],
     ["--query-file", query_path, "--file"], ["--query-file", query_path, "--unknown"],
     ["--query", query_path], ["--q", query_path], ["--query-file", query_path, "--help"],
     ["--version", "--query-file", query_path], ["--query-file", query_path, "--", "--validate"],
     ["--validate", "--query-file", query_path, "--file", document_path],
     ["--query-file", query_path, "--validate", "--validate"],
     ["--validate", "@", "extra"], ["--file", document_path, "--validate", "@"]].each do |arguments|
      original = arguments.dup
      expect(run_cli(arguments.freeze)).to eq([2, "", usage])
      expect(arguments).to eq(original)
    end
  end

  {
    "['✓',\n items[\n" => "Expected an array index at line 3, column 1\n\n^\n",
    "" => "Expected an expression at line 1, column 1\n\n^\n",
    "\xFF".b => "Expression has invalid encoding\n"
  }.each do |source, diagnostic|
    it "reports syntax for file source #{source.inspect}" do
      File.binwrite(query_path, source)
      expect(run_cli(["--query-file", query_path, "--file", document_path])).to eq([1, "", diagnostic])
      expect(run_cli(["--validate", "--query-file", query_path])).to eq([1, "", diagnostic])
    end
  end

  {
    "['✓',\n length(@)]\n" => "Invalid argument 1 for length: expected string, array, or object; received number " \
                              "at line 2, column 2\n length(@)]\n ^\n",
    "['✓',\n length()]\n" => "Invalid number of arguments for length: expected 1; received 0 " \
                             "at line 2, column 2\n length()]\n ^\n",
    "['✓', length(@)]\n" => "Invalid argument 1 for length: expected string, array, or object; received number " \
                            "at line 1, column 7\n['✓', length(@)]\n      ^\n",
    "lenght(@)\n" => "Unknown function: lenght. Did you mean length?\n"
  }.each do |source, diagnostic|
    it "retains runtime source context for #{source.inspect}" do
      File.binwrite(query_path, source)
      File.write(document_path, "4")
      expect(run_cli(["--query-file", query_path], input: StringIO.new("4"))).to eq([1, "", diagnostic])
      expect(run_cli(["--query-file", query_path, "--file", document_path])).to eq([1, "", diagnostic])
    end
  end

  it "passes the complete CRLF source to execution and validation" do
    source = "[\r\n '✓',\r\n user.name\r\n]\r\n"
    File.binwrite(query_path, source)
    allow(JMESPath).to receive(:search).and_wrap_original do |call, expression, data|
      expect(expression).to eq(source)
      call.call(expression, data)
    end
    allow(JMESPath).to receive(:validate).and_wrap_original do |call, expression|
      expect(expression).to eq(source)
      call.call(expression)
    end
    expect(run_cli(["--query-file", query_path, "--file", document_path])).to eq([0, "[\"✓\",\"café\"]\n", ""])
    expect(run_cli(["--query-file", query_path, "--validate"])).to eq([0, "", ""])
  end

  it "retains malformed JSON precedence over readable invalid queries" do
    File.write(document_path, '{"private_marker":BROKEN}')
    ["items[\n", "\xFF".b].each do |source|
      File.binwrite(query_path, source)
      expect(run_cli(["--query-file", query_path, "--file", document_path]))
        .to eq([1, "", "Invalid JSON input\n"])
    end
  end

  [Encoding::US_ASCII, Encoding::UTF_16LE].each do |encoding|
    it "preserves UTF-8 source when default internal encoding is #{encoding}" do
      File.binwrite(query_path, "['café', length(@)]\n")
      previous = Encoding.default_internal
      Encoding.default_internal = encoding
      expect(run_cli(["--query-file", query_path], input: StringIO.new("4")))
        .to eq([1, "", "Invalid argument 1 for length: expected string, array, or object; received number " \
                       "at line 1, column 10\n['café', length(@)]\n         ^\n"])
      expect(run_cli(["--validate", "--query-file", query_path])).to eq([0, "", ""])
      expect(run_cli(["--query-file", query_path], input: StringIO.new("BROKEN")))
        .to eq([1, "", "Invalid JSON input\n"])
      File.binwrite(query_path, "\xFF".b)
      expect(run_cli(["--query-file", query_path], input: StringIO.new("BROKEN")))
        .to eq([1, "", "Invalid JSON input\n"])
      expect(run_cli(["--validate", "--query-file", query_path]))
        .to eq([1, "", "Expression has invalid encoding\n"])
    ensure
      Encoding.default_internal = previous
    end
  end

  it "closes the query before opening the document and propagates evaluation errors" do
    opened = nil
    allow(File).to receive(:open).and_wrap_original do |call, path, *args, &block|
      expect(opened).to be_closed if path == document_path
      call.call(path, *args) do |file|
        opened = file if path == query_path
        block.call(file)
      end
    end
    input = StringIO.new
    input.close
    expect(run_cli(["--query-file", query_path, "--file", document_path], input: input))
      .to eq([0, "\"café\"\n", ""])
    failure = RuntimeError.new("evaluation failure")
    allow(JMESPath).to receive(:search).and_raise(failure)
    expect { run_cli(["--query-file", query_path, "--file", document_path]) }
      .to(raise_error { |error| expect(error).to equal(failure) })
    expect(opened).to be_closed
  end

  it "reports escaped missing paths before opening document input" do
    missing = File.join(@directory, "missing\n\e")
    allow(File).to receive(:open).and_call_original
    expect(File).not_to receive(:open).with(document_path, anything)
    status, output, errors = run_cli(["--query-file", missing, "--file", document_path])
    expect([status, output]).to eq([1, ""])
    expect(errors).to include("No such file or directory", "missing\\n\\e")
    expect(errors.lines.length).to eq(1)
    expect(run_cli(["--query-file", missing]).first).to eq(1)
  end

  it "reports permission failures before accessing document input" do
    allow(File).to receive(:open).and_call_original
    allow(File).to receive(:open).with(query_path, "rb:UTF-8:-").and_raise(Errno::EACCES, query_path)
    expect(File).not_to receive(:open).with(document_path, anything)
    status, output, errors = run_cli(["--query-file", query_path, "--file", document_path])
    expect([status, output]).to eq([1, ""])
    expect(errors).to include("Permission denied", query_path)
  end

  [nil, IOError.new("Read\nfailed\e"), Errno::EIO.new("Read\nfailed\e"),
   RuntimeError.new("unexpected")].each do |failure|
    it "closes the owned query file after #{failure&.class || 'success'}" do
      opened = nil
      allow(File).to receive(:open).and_call_original
      allow(File).to receive(:open).with(query_path, "rb:UTF-8:-").and_wrap_original do |call, *args, &block|
        call.call(*args) do |file|
          opened = file
          allow(file).to receive(:read).and_raise(failure) if failure
          block.call(file)
        end
      end
      allow(JMESPath).to receive(:validate).and_wrap_original do |call, *args|
        expect(opened).to be_closed
        call.call(*args)
      end
      if failure.instance_of?(RuntimeError)
        expect { run_cli(["--query-file", query_path, "--validate"]) }
          .to(raise_error { |error| expect(error).to equal(failure) })
      else
        status, output, errors = run_cli(["--query-file", query_path, "--validate"])
        expect([status, output]).to eq([failure ? 1 : 0, ""])
        expect(errors).to include("Read\\nfailed\\e") if failure
      end
      expect(opened).to be_closed
    end
  end

  %w[jmespath jmespath.rb].each do |name|
    it "executes file queries through #{name} with either document source" do
      executable = File.expand_path("../../exe/#{name}", __dir__)
      [["--query-file", query_path], ["--query-file", query_path, "--file", document_path]].each do |arguments|
        output, errors, status = Open3.capture3(RbConfig.ruby, executable, *arguments, stdin_data: document)
        expect([status.exitstatus, output, errors]).to eq([0, "\"café\"\n", ""])
      end
    end

    {
      "['✓',\n items[\n" => "Expected an array index at line 3, column 1\n\n^\n",
      "['✓',\n length(@)]\n" => "Invalid argument 1 for length: expected string, array, or object; received number " \
                                "at line 2, column 2\n length(@)]\n ^\n",
      "['✓',\n length()]\n" => "Invalid number of arguments for length: expected 1; received 0 " \
                               "at line 2, column 2\n length()]\n ^\n"
    }.each do |source, diagnostic|
      it "reports #{source.inspect} through #{name}" do
        File.binwrite(query_path, source)
        output, errors, status = Open3.capture3(
          RbConfig.ruby, File.expand_path("../../exe/#{name}", __dir__), "--query-file", query_path, stdin_data: "4"
        )
        expect([status.exitstatus, output, errors]).to eq([1, "", diagnostic])
      end
    end

    it "finishes validation and early failures through #{name} while stdin remains open" do
      executable = File.expand_path("../../exe/#{name}", __dir__)
      missing = File.join(@directory, "missing")
      {
        ["--validate", "--query-file", query_path] => 0,
        ["--query-file", query_path, "--validate"] => 0,
        ["--query-file", missing] => 1,
        ["--query-file", query_path, "@"] => 2,
        ["--query-file"] => 2
      }.each do |arguments, expected_status|
        Open3.popen3(RbConfig.ruby, executable, *arguments) do |input, output, errors, waiter|
          status = Timeout.timeout(5) { waiter.value }
          expect(input).not_to be_closed
          expect([status.exitstatus, output.read]).to eq([expected_status, ""])
          diagnostic = errors.read
          case expected_status
          when 0 then expect(diagnostic).to eq("")
          when 1 then expect(diagnostic).to include("No such file or directory", missing)
          when 2 then expect(diagnostic).to eq(usage)
          end
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
