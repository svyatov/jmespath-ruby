# frozen_string_literal: true

require "open3"
require "rbconfig"
require "stringio"
require "timeout"
require "tmpdir"
require "jmespath/cli"

RSpec.describe "Command-line raw output" do
  around do |example|
    Dir.mktmpdir("jmespath-raw") do |directory|
      @directory = directory
      example.run
    end
  end

  let(:query_path) { File.join(@directory, "query.jmespath") }
  let(:document_path) { File.join(@directory, "document.json") }
  let(:document) { '"Ada\n"' }
  let(:raw_document) { "Ada\n\n" }

  before do
    File.binwrite(query_path, "@\n")
    File.write(document_path, document)
  end

  def run_cli(arguments, input: double("unused stdin"))
    output = StringIO.new.set_encoding(Encoding::UTF_8)
    errors = StringIO.new.set_encoding(Encoding::UTF_8)
    status = JMESPath::CLI.run(arguments, stdin: input, stdout: output, stderr: errors)
    [status, output.string, errors.string]
  end

  def usage
    "Usage: jmespath [--pretty | --raw-output | --json-lines] [--file PATH] " \
      "(EXPRESSION | --query-file PATH)\n       " \
      "jmespath --validate (EXPRESSION | --query-file PATH)\n       jmespath --functions\n"
  end

  {
    '""' => "\n", '"café ✓"' => "café ✓\n",
    '"a\"b"' => "a\"b\n", '"a\\\\b"' => "a\\b\n",
    '"a\nb"' => "a\nb\n", '"a\n"' => "a\n\n",
    '"a\n\n"' => "a\n\n\n", '"\n"' => "\n\n"
  }.each do |input, expected|
    it "preserves raw string bytes and appends one newline for #{input}" do
      expect(run_cli(["--raw-output", "@"], input: StringIO.new(input))).to eq([0, expected, ""])
      expect(run_cli(["@"], input: StringIO.new(input))).to eq([0, "#{input}\n", ""])
    end
  end

  ['["a"]', '{"a":"b"}', "[]", "{}", "42", "1.5", "true", "false", "null"].each do |input|
    it "retains JSON for the non-string result #{input}" do
      expect(run_cli(["--raw-output", "@"], input: StringIO.new(input))).to eq([0, "#{input}\n", ""])
      expect(run_cli(["@"], input: StringIO.new(input))).to eq([0, "#{input}\n", ""])
    end
  end

  it "supports a puts-only output stream" do
    output = double("puts-only output")
    expect(output).to receive(:puts).with("Ada\n\n")
    status = JMESPath::CLI.run(["--raw-output", "@"], stdin: StringIO.new(document), stdout: output)
    expect(status).to eq(0)
  end

  it "supports each query and document source without changing arguments" do
    [["--raw-output", "@"], ["@", "--raw-output"], ["--raw-output", "--", "@"],
     ["--raw-output", "--query-file", query_path]].each do |arguments|
      original = arguments.dup
      expect(run_cli(arguments.freeze, input: StringIO.new(document))).to eq([0, raw_document, ""])
      expect(arguments).to eq(original)
    end
    [["--raw-output", "@", "--file", document_path], ["--file=#{document_path}", "@", "--raw-output"],
     ["--raw-output", "--query-file", query_path, "--file", document_path],
     ["--file=#{document_path}", "--query-file=#{query_path}", "--raw-output"]].each do |arguments|
      original = arguments.dup
      expect(run_cli(arguments.freeze)).to eq([0, raw_document, ""])
      expect(arguments).to eq(original)
    end
  end

  it "formats the query result rather than the input document" do
    expect(run_cli(["--raw-output", "user.name"], input: StringIO.new('{"user":{"name":"Ada"}}')))
      .to eq([0, "Ada\n", ""])
  end

  it "retains trailing options under POSIXLY_CORRECT" do
    previous = ENV.fetch("POSIXLY_CORRECT", nil)
    ENV["POSIXLY_CORRECT"] = "1"
    expect(run_cli(["@", "--raw-output"], input: StringIO.new(document))).to eq([0, raw_document, ""])
  ensure
    ENV["POSIXLY_CORRECT"] = previous
  end

  it "rejects unsupported arguments before input access" do
    allow(File).to receive(:open).and_raise("unexpected file access")
    [["--raw-output"], %w[--raw-output --raw-output @], %w[--raw-output=true @], %w[--raw @], %w[-r @],
     %w[--raw_output @], %w[--raw_output=true @],
     %w[--raw-output @ extra], %w[--raw-output -- @ extra], %w[--raw-output --validate @],
     %w[--validate @ --raw-output], %w[--raw-output --pretty @], %w[--pretty --raw-output @],
     ["--raw-output", "--pretty", "--query-file", query_path, "--file", document_path],
     ["--file", document_path, "--pretty", "--query-file", query_path, "--raw-output"],
     ["--raw-output", "--query-file", query_path, "@"],
     ["--raw-output", "--validate", "--query-file", query_path],
     ["--query-file", query_path, "--validate", "--raw-output"],
     ["--raw-output", "--validate", "--query-file", query_path, "--file", document_path],
     ["--file", document_path, "--query-file", query_path, "--validate", "--raw-output"]].each do |arguments|
      original = arguments.dup
      expect(run_cli(arguments.freeze)).to eq([2, "", usage])
      expect(arguments).to eq(original)
    end
    %w[--help -h --version].each do |flag|
      expect(run_cli([flag, "--raw-output"])).to eq([2, "", usage])
      expect(run_cli(["--raw-output", flag])).to eq([2, "", usage])
    end
  end

  it "keeps flag-like filenames and query text literal" do
    Dir.chdir(@directory) do
      File.write("--raw_output", document)
      expect(run_cli(["--raw-output", "--file", "--raw_output", "@"]))
        .to eq([0, raw_document, ""])
      File.write("--raw_output", "@")
      %w[--query-file --query_file].each do |flag|
        expect(run_cli(["--raw-output", flag, "--raw_output"], input: StringIO.new(document)))
          .to eq([0, raw_document, ""])
      end
    end
    diagnostic = "Expected a digit at line 1, column 1\n--raw_output\n^\n"
    expect(run_cli(["--validate", "--raw_output"])).to eq([1, "", diagnostic])
    expect(run_cli(["--raw-output", "--", "--raw_output"], input: StringIO.new(document)))
      .to eq([1, "", diagnostic])
  end

  it "preserves literal two-argument validation and the option delimiter" do
    allow(File).to receive(:open).and_raise("unexpected file access")
    diagnostic = "Expected a digit at line 1, column 1\n--raw-output\n^\n"
    expect(run_cli(["--validate", "--raw-output"])).to eq([1, "", diagnostic])
    expect(run_cli(["--", "--raw-output"], input: StringIO.new(document))).to eq([1, "", diagnostic])
  end

  {
    "items[" => ["{}", "Expected an array index at line 1, column 7\nitems[\n      ^\n"],
    "length(@)" => ["4", "Invalid argument 1 for length: expected string, array, or object; received number " \
                         "at line 1, column 1\nlength(@)\n^\n"],
    "length()" => ["{}", "Invalid number of arguments for length: expected 1; received 0 " \
                         "at line 1, column 1\nlength()\n^\n"],
    "lenght(@)" => ["{}", "Unknown function: lenght. Did you mean length?\n"],
    "[::0]" => ["[]", "Slice step cannot be zero\n"],
    "@" => ['{"private_marker":BROKEN}', "Invalid JSON input\n"],
    "['✓',\n items[\n" => ["4", "Expected an array index at line 3, column 1\n\n^\n"],
    "['✓', length(@)]\n" => ["4", "Invalid argument 1 for length: expected string, array, or object; " \
                                  "received number at line 1, column 7\n['✓', length(@)]\n      ^\n"],
    "['✓',\n length()]\n" => ["4", "Invalid number of arguments for length: expected 1; received 0 " \
                                   "at line 2, column 2\n length()]\n ^\n"]
  }.each do |query, (input, diagnostic)|
    it "preserves complete failure results for #{query.inspect}" do
      File.binwrite(query_path, query)
      File.write(document_path, input)
      [[query], ["--query-file", query_path],
       ["--query-file", query_path, "--file", document_path]].each do |arguments|
        [arguments, ["--raw-output", *arguments]].each do |options|
          expect(run_cli(options, input: StringIO.new(input))).to eq([1, "", diagnostic])
        end
      end
    end
  end

  it "reports missing input files with escaped errors" do
    missing = File.join(@directory, "missing\n\e")
    [["--raw-output", "--query-file", missing], ["--raw-output", "--file", missing, "@"]].each do |arguments|
      status, output, errors = run_cli(arguments)
      expect([status, output]).to eq([1, ""])
      expect(errors).to include("No such file or directory", "missing\\n\\e")
      expect(errors.lines.length).to eq(1)
    end
  end

  [RuntimeError, ArgumentError].each do |type|
    it "propagates unrelated #{type} evaluation failures" do
      failure = type.new("Application failure")
      allow(JMESPath).to receive(:search).with("@", {}).and_raise(failure)
      expect { run_cli(["--raw-output", "@"], input: StringIO.new("{}")) }
        .to(raise_error { |error| expect(error).to equal(failure) })
    end
  end

  it "explains output formatting and validation conflicts in help" do
    status, output, errors = run_cli(["--help"])
    expect([status, errors]).to eq([0, ""])
    expect(output).to include("--raw-output", "string", "newline", "--pretty", "repeated", "--validate")
  end

  %w[jmespath jmespath.rb].each do |name|
    it "preserves output and failures through #{name}" do
      executable = File.expand_path("../../exe/#{name}", __dir__)
      {
        [[], "@", document] => [0, "#{document}\n", ""],
        [["--raw-output"], "@", document] => [0, raw_document, ""],
        [["--raw-output"], "@", '["Ada"]'] => [0, "[\"Ada\"]\n", ""],
        [["--raw-output"], "items[", "{}"] => [1, "", "Expected an array index at line 1, column 7\nitems[\n      ^\n"],
        [["--raw-output"], "length(@)",
         "4"] => [1, "", "Invalid argument 1 for length: expected string, array, or object; " \
                         "received number at line 1, column 1\nlength(@)\n^\n"],
        [["--raw-output"], "@", "BROKEN"] => [1, "", "Invalid JSON input\n"]
      }.each do |(options, query, input), expected|
        output, errors, status = Open3.capture3(RbConfig.ruby, executable, *options, query, stdin_data: input)
        expect([status.exitstatus, output, errors]).to eq(expected)
      end
    end

    it "rejects formatting conflicts through #{name} while stdin remains open" do
      Open3.popen3(RbConfig.ruby, File.expand_path("../../exe/#{name}", __dir__),
                   "--raw-output", "--pretty", "--query-file", query_path) do |input, output, errors, waiter|
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
