# frozen_string_literal: true

require "open3"
require "rbconfig"
require "stringio"
require "tmpdir"
require "jmespath/cli"

RSpec.describe "Command-line document files" do
  around do |example|
    Dir.mktmpdir("jmespath-cli") do |directory|
      @directory = directory
      example.run
    end
  end

  let(:path) { File.join(@directory, "document.json") }
  let(:unreadable_input) { double("unused stdin") }

  before { File.write(path, '{"user":{"name":"café"}}', encoding: "UTF-8") }

  def usage
    "Usage: jmespath [--file PATH] EXPRESSION\n       jmespath --validate EXPRESSION\n"
  end

  def run_cli(arguments, input: unreadable_input)
    output = StringIO.new
    errors = StringIO.new
    status = JMESPath::CLI.run(arguments, stdin: input, stdout: output, stderr: errors)
    [status, output.string, errors.string]
  rescue SystemExit => e
    raise "CLI.run exited the process with status #{e.status}"
  end

  def observe_file
    opened = []
    allow(File).to receive(:open).and_wrap_original do |original, *arguments, &block|
      original.call(*arguments) do |file|
        opened << file
        block.call(file)
      end
    end
    opened
  end

  it "reads UTF-8 files with options before or after the query without changing arguments" do
    [["--file", path, "user.name"], ["user.name", "--file", path],
     ["--file=#{path}", "user.name"], ["--file", path, "--", "user.name"]].each do |arguments|
      original = arguments.dup
      expect(run_cli(arguments.freeze)).to eq([0, "\"café\"\n", ""])
      expect(arguments).to eq(original)
    end
  end

  it "keeps parsing options after the query under POSIXLY_CORRECT" do
    previous = ENV.fetch("POSIXLY_CORRECT", nil)
    ENV["POSIXLY_CORRECT"] = "1"
    expect(run_cli(["user.name", "--file", path])).to eq([0, "\"café\"\n", ""])
  ensure
    ENV["POSIXLY_CORRECT"] = previous
  end

  it "reads spaces and option-like filenames as literal paths" do
    ["my document.json", "--document.json", "-"].each do |name|
      File.write(File.join(@directory, name), "2")
      Dir.chdir(@directory) do
        expect(run_cli(["--file=#{name}", "@"]))
          .to eq([0, "2\n", ""])
        expect(run_cli(["--file", "./#{name}", "@"]))
          .to eq([0, "2\n", ""])
      end
    end
    Dir.chdir(@directory) do
      expect(run_cli(["--file", "-", "@"]))
        .to eq([0, "2\n", ""])
    end
  end

  it "ignores a closed stdin when a file is selected" do
    input = StringIO.new
    input.close
    expect(run_cli(["--file", path, "user.name"], input: input)).to eq([0, "\"café\"\n", ""])
  end

  it "retains caller ownership of stdin and positional queries" do
    input = StringIO.new('{"foo":{"bar":2}}')
    expect(run_cli(["foo.bar"], input: input)).to eq([0, "2\n", ""])
    expect(input).not_to be_closed
    expect(run_cli(["--", "foo.bar"], input: StringIO.new('{"foo":{"bar":2}}'))).to eq([0, "2\n", ""])
  end

  [[], ["--unknown"], ["--file"], ["--file", "PATH"], ["--"], ["--", "@", "extra"],
   ["--file", "PATH", "--file", "PATH", "@"], ["--file", "PATH", "@", "extra"],
   ["--", "--file", "PATH", "@"], ["-f", "PATH", "@"],
   ["--f", "PATH", "@"], ["--fi=PATH", "@"], ["--fil", "PATH", "@"],
   ["--*-completion-bash", "@"], ["--*-completion-zsh", "@"]].each do |arguments|
    it "rejects malformed arguments #{arguments.inspect} without accessing input" do
      allow(File).to receive(:open).and_raise("must not open a file")
      original = arguments.dup
      expect(run_cli(arguments.freeze)).to eq([2, "", usage])
      expect(arguments).to eq(original)
    end
  end

  %w[--help -h --version].each do |flag|
    it "handles standalone #{flag} without accessing input and rejects combinations" do
      allow(File).to receive(:open).and_raise("must not open a file")
      status, output, errors = run_cli([flag])
      expect([status, errors]).to eq([0, ""])
      expect(output).not_to be_empty
      [[flag, "@"], ["--file", path, flag], [flag, "--file", path, "@"]].each do |arguments|
        expect(run_cli(arguments)).to eq([2, "", usage])
      end
    end
  end

  it "preserves an empty expression as a query failure" do
    expect(run_cli(["--file", path, ""]).take(2)).to eq([1, ""])
  end

  it "keeps syntax validation independent from file input" do
    allow(File).to receive(:open).and_raise("must not open a file")
    expect(run_cli(["--validate", "unknown()"])).to eq([0, "", ""])
    [["--validate", "@", "--file", path], ["--file", path, "--validate", "@"],
     ["@", "--file", path, "--validate"]].each do |arguments|
      expect(run_cli(arguments)).to eq([2, "", usage])
    end
  end

  it "reports missing files with escaped paths" do
    missing = File.join(@directory, "missing\n\e.json")
    status, output, errors = run_cli(["--file", missing, "@"])
    expect([status, output]).to eq([1, ""])
    expect(errors).to include("No such file or directory", "missing\\n\\e.json")
    expect(errors.lines.length).to eq(1)
    expect(errors).not_to include("\e")
  end

  it "reports permission failures without falling back to stdin" do
    allow(File).to receive(:open).with(path, "r:UTF-8").and_raise(Errno::EACCES, path)
    status, output, errors = run_cli(["--file", path, "@"])
    expect([status, output]).to eq([1, ""])
    expect(errors).to include("Permission denied", path)
  end

  it "closes files after successful reads before evaluating the query" do
    opened = observe_file
    allow(JMESPath).to receive(:search).and_wrap_original do |call, *args|
      expect(opened.length).to eq(1)
      expect(opened.first).to be_closed
      call.call(*args)
    end
    expect(run_cli(["--file", path, "user.name"])).to eq([0, "\"café\"\n", ""])
    expect(opened.first).to be_closed
  end

  it "closes malformed JSON without exposing its contents or evaluating the query" do
    File.write(path, '{"private_marker":BROKEN}')
    opened = observe_file
    expect(run_cli(["--file", path, "items["])).to eq([1, "", "Invalid JSON input\n"])
    expect(opened.first).to be_closed
  end

  [IOError.new("Read\nfailed\e"), Errno::EIO.new("Read\nfailed\e")].each do |failure|
    it "closes files after #{failure.class} read failures" do
      opened = []
      allow(File).to receive(:open).with(path, "r:UTF-8").and_wrap_original do |original, *args, &block|
        original.call(*args) do |file|
          opened << file
          allow(file).to receive(:read).and_raise(failure)
          block.call(file)
        end
      end
      status, output, errors = run_cli(["--file", path, "@"])
      expect([status, output]).to eq([1, ""])
      expect(errors).to include("Read\\nfailed\\e\n")
      expect(opened.first).to be_closed
    end
  end

  it "propagates unexpected evaluation errors after closing the document" do
    opened = observe_file
    failure = RuntimeError.new("Application failure")
    allow(JMESPath).to receive(:search).and_raise(failure)
    expect { run_cli(["--file", path, "@"]) }.to(raise_error { |error| expect(error).to equal(failure) })
    expect(opened.first).to be_closed
  end

  {
    "items[" => "Expected an array index at line 1, column 7\nitems[\n      ^\n",
    "length(@)" => "Invalid argument 1 for length: expected string, array, or object; received number " \
                   "at line 1, column 1\nlength(@)\n^\n",
    "length()" => "Invalid number of arguments for length: expected 1; received 0 " \
                  "at line 1, column 1\nlength()\n^\n",
    "['✓', length(@)]" => "Invalid argument 1 for length: expected string, array, or object; received number " \
                          "at line 1, column 7\n['✓', length(@)]\n      ^\n",
    "lenght(@)" => "Unknown function: lenght. Did you mean length?\n"
  }.each do |query, diagnostic|
    it "retains diagnostics and closes files for #{query.inspect}" do
      File.write(path, "4")
      opened = observe_file
      [["--file", path, query], [query, "--file", path]].each do |arguments|
        expect(run_cli(arguments)).to eq([1, "", diagnostic])
      end
      expect(opened.length).to eq(2)
      expect(opened).to all(be_closed)
    end
  end

  it "explains file input and literal paths in help" do
    status, output, errors = run_cli(["--help"])
    expect([status, errors]).to eq([0, ""])
    expect(output).to include("--file PATH", "UTF-8", "--file -", "--file=--document.json", "'my document.json'")
  end

  %w[jmespath jmespath.rb].each do |name|
    def executable(name, arguments, input = "invalid stdin")
      output, errors, status = Open3.capture3(
        RbConfig.ruby, File.expand_path("../../exe/#{name}", __dir__), *arguments,
        stdin_data: input, chdir: @directory
      )
      [status.exitstatus, output, errors]
    end

    it "runs file paths and option placement through #{name}" do
      ["my document.json", "--document.json", "-"].each do |filename|
        File.write(File.join(@directory, filename), '{"name":"café"}', encoding: "UTF-8")
        [["--file=#{filename}", "name"], ["name", "--file", "./#{filename}"]].each do |arguments|
          expect(executable(name, arguments)).to eq([0, "\"café\"\n", ""])
        end
      end
      expect(executable(name, ["--file", "-", "name"])).to eq([0, "\"café\"\n", ""])
    end

    {
      "items[" => "Expected an array index at line 1, column 7\nitems[\n      ^\n",
      "length(@)" => "Invalid argument 1 for length: expected string, array, or object; received number " \
                     "at line 1, column 1\nlength(@)\n^\n",
      "length()" => "Invalid number of arguments for length: expected 1; received 0 " \
                    "at line 1, column 1\nlength()\n^\n",
      "['✓', length(@)]" => "Invalid argument 1 for length: expected string, array, or object; received number " \
                            "at line 1, column 7\n['✓', length(@)]\n      ^\n"
    }.each do |query, diagnostic|
      it "retains #{query.inspect} diagnostics through #{name}" do
        File.write(path, "4")
        expect(executable(name, ["--file", path, query])).to eq([1, "", diagnostic])
      end
    end

    it "reports file and usage failures through #{name}" do
      missing = File.join(@directory, "missing.json")
      status, output, errors = executable(name, ["--file", missing, "@"])
      expect([status, output]).to eq([1, ""])
      expect(errors).to include("No such file or directory", missing)
      expect(errors).not_to include("\e", "cli.rb:")
      File.write(path, '{"private_marker":BROKEN}')
      expect(executable(name, ["--file", path, "items["])).to eq([1, "", "Invalid JSON input\n"])
      expect(executable(name, ["--file"]))
        .to eq([2, "", usage])
    end

    it "reports unreadable document paths through #{name}" do
      status, output, errors = executable(name, ["--file", @directory, "@"])
      expect([status, output]).to eq([1, ""])
      expect(errors).to include("Is a directory", @directory)
    end
  end
end
