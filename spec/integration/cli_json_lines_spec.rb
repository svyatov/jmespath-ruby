# frozen_string_literal: true

require "open3"
require "rbconfig"
require "stringio"
require "timeout"
require "tmpdir"
require "jmespath/cli"

RSpec.describe "Command-line JSON Lines" do
  around do |example|
    Dir.mktmpdir("jmespath-lines") do |directory|
      @directory = directory
      example.run
    end
  end

  let(:path) { File.join(@directory, "records.jsonl") }
  let(:query_path) { File.join(@directory, "query.jmespath") }

  before do
    File.write(path, "1\n2\n")
    File.write(query_path, "@")
  end

  def usage
    "Usage: jmespath [--pretty | --raw-output | --json-lines] [--file PATH] " \
      "(EXPRESSION | --query-file PATH)\n       " \
      "jmespath --validate (EXPRESSION | --query-file PATH)\n"
  end

  def run_cli(arguments, input: double("unused stdin"), output: StringIO.new)
    errors = StringIO.new
    status = JMESPath::CLI.run(arguments, stdin: input, stdout: output, stderr: errors)
    [status, output.string, errors.string]
  end

  it "writes one compact result for each record, including missing and false values" do
    input = StringIO.new("{\"user\":{\"name\":\"café\"}}\n{}\n{\"user\":{\"name\":false}}")
    expect(run_cli(["--json-lines", "user.name"], input: input)).to eq([0, "\"café\"\nnull\nfalse\n", ""])
    expect(input).not_to be_closed
  end

  it "preserves all JSON types with LF, CRLF, and an unterminated final record" do
    input = "{}\n[]\n\"café\"\n42\n1.5\ntrue\nfalse\nnull"
    [input, input.gsub("\n", "\r\n")].each do |records|
      expect(run_cli(["--json-lines", "@"], input: StringIO.new(records))).to eq([0, "#{input}\n", ""])
    end
  end

  it "rejects invalid UTF-8 without leaking record contents or writing a result" do
    ["1\n\"private_\xff\"\n2\n".b, "1\n\"private_\xff\"\n2\n".b.force_encoding(Encoding::UTF_8)].each do |records|
      expect(run_cli(["--json-lines", "@"], input: StringIO.new(records)))
        .to eq([1, "1\n", "Input line 2:\nInvalid JSON input\n"])
    end
    File.binwrite(path, "1\n\"private_\xff\"\n2\n".b)
    expect(run_cli(["--json-lines", "--file", path, "@"]))
      .to eq([1, "1\n", "Input line 2:\nInvalid JSON input\n"])
  end

  it "reports an unrepresentable result and stops before reading the next record" do
    input = StringIO.new("1\n1e400\n2\n")
    expect(run_cli(["--json-lines", "@"], input: input))
      .to eq([1, "1\n", "Input line 2:\nInvalid JSON result\n"])
    expect(input.gets).to eq("2\n")
  end

  ["", "1\n2\n"].each do |records|
    it "compiles once before processing #{records.inspect}" do
      expect(JMESPath).to receive(:compile).with("@").once.and_call_original
      expect(run_cli(["--json-lines", "@"], input: StringIO.new(records))).to eq([0, records, ""])
    end
  end

  it "rejects invalid syntax before opening the document or reading stdin" do
    allow(File).to receive(:open).and_raise("unexpected input access")
    expect(run_cli(["--json-lines", "items[", "--file", "missing"]))
      .to eq([1, "", "Expected an array index at line 1, column 7\nitems[\n      ^\n"])
    expect(run_cli(["--json-lines", "items["], input: StringIO.new("")))
      .to eq([1, "", "Expected an array index at line 1, column 7\nitems[\n      ^\n"])
  end

  it "reports missing query and document files without a record number" do
    [["--query-file", "missing-query", "--file", "missing-document"], ["--file", "missing-document", "@"]]
      .each do |arguments|
      status, output, errors = run_cli(["--json-lines", *arguments])
      expect([status, output]).to eq([1, ""])
      expect(errors).to include(arguments[1])
      expect(errors).not_to include("Input line")
    end
  end

  ["BROKEN\n", "\n", " \t\r\n", "{\"private_marker\":BROKEN}\n", "{\n  \"a\":1\n}\n"].each do |bad|
    it "retains earlier output and stops at malformed record #{bad.inspect}" do
      input = double("line reader")
      expect(input).to receive(:gets).ordered.and_return("1\n")
      expect(input).to receive(:gets).ordered.and_return(bad.lines.first)
      expect(run_cli(["--json-lines", "@"], input: input))
        .to eq([1, "1\n", "Input line 2:\nInvalid JSON input\n"])
    end
  end

  it "retains query context separately from the failing input line" do
    File.write(query_path, "['✓',\n length(@)]\n")
    input = double("line reader")
    expect(input).to receive(:gets).ordered.and_return("[]\n")
    expect(input).to receive(:gets).ordered.and_return("4\n")
    expect(run_cli(["--json-lines", "--query-file", query_path], input: input))
      .to eq([1, "[\"✓\",0]\n", "Input line 2:\nInvalid argument 1 for length: " \
                                "expected string, array, or object; received number at line 2, column 2\n " \
                                "length(@)]\n ^\n"])
  end

  {
    "length()" => "Invalid number of arguments for length: expected 1; received 0 " \
                  "at line 1, column 1\nlength()\n^\n",
    "lenght(@)" => "Unknown function: lenght. Did you mean length?\n"
  }.each do |query, diagnostic|
    it "adds record context to #{query} failures" do
      expect(run_cli(["--json-lines", query], input: StringIO.new("[]\n")))
        .to eq([1, "", "Input line 1:\n#{diagnostic}"])
    end
  end

  it "reports compile-time invalid values without record context" do
    expect(run_cli(["--json-lines", "[::0]"], input: StringIO.new("[]\n")))
      .to eq([1, "", "Slice step cannot be zero\n"])
  end

  it "retains output when a later function cannot serialize its value" do
    nested = "#{'[' * 100}0#{']' * 100}"
    expect(run_cli(["--json-lines", "to_string([@])"], input: StringIO.new("1\n#{nested}\n2\n")))
      .to eq([1, "\"[1]\"\n", "Input line 2:\nValue is too deeply nested to serialize\n"])
  end

  it "writes each result before requesting the next record without whole-stream reads" do
    input = double("gets-only reader")
    output = StringIO.new
    expect(input).to receive(:gets).ordered.and_return("1\n")
    expect(output).to receive(:puts).with("1").ordered.and_call_original
    expect(input).to receive(:gets).ordered.and_return("2\n")
    expect(output).to receive(:puts).with("2").ordered.and_call_original
    expect(input).to receive(:gets).ordered.and_return(nil)
    expect(run_cli(["--json-lines", "@"], input: input, output: output)).to eq([0, "1\n2\n", ""])
    expect(output).not_to be_closed
    expect(run_cli(["@"], input: double("read-only reader", read: "1"))).to eq([0, "1\n", ""])
  end

  [IOError, Errno::EIO].each do |type|
    it "identifies the next line when a #{type} read fails" do
      input = double("failing reader")
      expect(input).to receive(:gets).ordered.and_return("1\n")
      expect(input).to receive(:gets).ordered.and_raise(type, "read failed")
      status, output, errors = run_cli(["--json-lines", "@"], input: input)
      expect([status, output]).to eq([1, "1\n"])
      expect(errors).to start_with("Input line 2:\n")
      expect(errors).to include("read failed")
    end
  end

  it "stops on output failure and retains caller stream ownership" do
    output = StringIO.new
    expect(output).to receive(:puts).with("1").and_call_original
    expect(output).to receive(:puts).with("2").and_raise(IOError, "write failed")
    input = StringIO.new("1\n2\n3\n")
    expect(run_cli(["--json-lines", "@"], input: input, output: output))
      .to eq([1, "1\n", "Input line 2:\nwrite failed\n"])
    expect(input.gets).to eq("3\n")
    expect(input).not_to be_closed
    expect(output).not_to be_closed
  end

  it "reports a closed input stream on line one" do
    input = StringIO.new
    input.close
    expect(run_cli(["--json-lines", "@"], input: input)).to eq([1, "", "Input line 1:\nnot opened for reading\n"])
  end

  [["@", "1\n2\n", 0], ["@", "1\nBROKEN\n", 1], ["length(@)", "[]\n4\n", 1]].each do |query, text, status|
    it "closes owned files after #{text.inspect} with #{query}" do
      File.write(path, text)
      opened = []
      allow(File).to receive(:open).and_wrap_original do |original, *arguments, &block|
        original.call(*arguments) do |file|
          opened << file
          block.call(file)
        end
      end
      expect(run_cli(["--json-lines", "--file", path, query]).first).to eq(status)
      expect(opened).not_to be_empty
      expect(opened).to all(be_closed)
    end
  end

  it "closes owned files after a read failure" do
    opened = nil
    allow(File).to receive(:open).with(path, "r:UTF-8").and_wrap_original do |original, *arguments, &block|
      original.call(*arguments) do |file|
        opened = file
        allow(file).to receive(:gets).and_raise(IOError, "read failed")
        block.call(file)
      end
    end
    expect(run_cli(["--json-lines", "--file", path, "@"]))
      .to eq([1, "", "Input line 1:\nread failed\n"])
    expect(opened).to be_closed
  end

  [RuntimeError, ArgumentError].each do |type|
    it "propagates unrelated #{type} errors" do
      compiled = instance_double(JMESPath::Expression)
      allow(JMESPath).to receive(:compile).with("@").and_return(compiled)
      allow(compiled).to receive(:search).with(1).and_raise(type, "Application failure")
      expect { run_cli(["--json-lines", "@"], input: StringIO.new("1\n")) }
        .to raise_error(type, "Application failure")
    end
  end

  it "supports query and input sources, option ordering, and frozen arguments" do
    [["--json-lines", "@"], ["@", "--json-lines"], ["--json-lines", "--", "@"],
     ["--json-lines", "--query-file", query_path]].each do |arguments|
      original = arguments.dup
      expect(run_cli(arguments.freeze, input: StringIO.new("1\n2\n"))).to eq([0, "1\n2\n", ""])
      expect(arguments).to eq(original)
    end
    [["--json-lines", "--file", path, "@"],
     ["--file=#{path}", "--query-file=#{query_path}", "--json-lines"]].each do |arguments|
      expect(run_cli(arguments.freeze)).to eq([0, "1\n2\n", ""])
    end
    ["-", "my records.jsonl", "--records.jsonl"].each do |name|
      File.write(File.join(@directory, name), "1\n2\n")
      Dir.chdir(@directory) do
        expect(run_cli(["--json-lines", "--file=#{name}", "@"]).first(2)).to eq([0, "1\n2\n"])
      end
    end
  end

  it "processes trailing options with POSIXLY_CORRECT" do
    previous = ENV.fetch("POSIXLY_CORRECT", nil)
    ENV["POSIXLY_CORRECT"] = "1"
    expect(run_cli(["@", "--json-lines"], input: StringIO.new("1\n"))).to eq([0, "1\n", ""])
  ensure
    ENV["POSIXLY_CORRECT"] = previous
  end

  it "rejects malformed options and mode conflicts before input access" do
    allow(File).to receive(:open).and_raise("unexpected file access")
    [%w[--json-lines], %w[--json-lines --json-lines @], %w[--json-lines=true @],
     %w[--json_lines @], %w[--json_lines=true @],
     %w[--json @], %w[-j @], %w[--json-lines @ extra], %w[--json-lines --pretty @],
     %w[--pretty --json-lines @], %w[--json-lines --raw-output @], %w[--raw-output --json-lines @],
     %w[--json-lines --validate @], %w[--validate @ --json-lines],
     ["--json-lines", "--validate", "--query-file", query_path],
     ["--validate", "--query-file", query_path, "--json-lines"],
     ["--json-lines", "--query-file", query_path, "@"]].each do |arguments|
      expect(run_cli(arguments.freeze)).to eq([2, "", usage])
    end
    %w[--help -h --version].each do |flag|
      expect(run_cli([flag]).first).to eq(0)
      expect(run_cli([flag, "--json-lines"])).to eq([2, "", usage])
    end
    expect(run_cli(%w[--validate --json-lines]))
      .to eq([1, "", "Expected a digit at line 1, column 1\n--json-lines\n^\n"])
  end

  %w[jmespath jmespath.rb].each do |name|
    it "processes streams and preserves partial output through #{name}" do
      executable = File.expand_path("../../exe/#{name}", __dir__)
      [["@", "1\n2", 0, "1\n2\n", ""], ["@", "", 0, "", ""],
       ["@", "1\nBROKEN\n2\n", 1, "1\n", "Input line 2:\nInvalid JSON input\n"],
       ["length(@)", "[]\n4\n", 1, "0\n", "Input line 2:\nInvalid argument 1 for length: " \
                                          "expected string, array, or object; received number " \
                                          "at line 1, column 1\nlength(@)\n^\n"],
       ["items[", "", 1, "", "Expected an array index at line 1, column 7\nitems[\n      ^\n"]]
        .each do |query, input, status, output, errors|
        actual_output, actual_errors, actual_status = Open3.capture3(RbConfig.ruby, executable,
                                                                     "--json-lines", query, stdin_data: input)
        expect([actual_status.exitstatus, actual_output, actual_errors]).to eq([status, output, errors])
      end
      output, errors, status = Open3.capture3(RbConfig.ruby, executable, "--json-lines",
                                              "--query-file", query_path, "--file", path)
      expect([status.exitstatus, output, errors]).to eq([0, "1\n2\n", ""])
    end

    it "rejects conflicts before stdin closes through #{name}" do
      Open3.popen3(RbConfig.ruby, File.expand_path("../../exe/#{name}", __dir__),
                   "--json-lines", "--validate", "--query-file", query_path) do |input, output, errors, waiter|
        status = Timeout.timeout(5) { waiter.value }
        expect(input).not_to be_closed
        expect([status.exitstatus, output.read, errors.read]).to eq([2, "", usage])
      ensure
        if waiter.alive?
          Process.kill("KILL", waiter.pid)
          waiter.value
        end
      end
    end
  end
end
