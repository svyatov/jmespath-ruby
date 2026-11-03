# frozen_string_literal: true

require "open3"
require "pty"
require "rbconfig"
require "stringio"
require "tmpdir"
require "timeout"
require "jmespath/cli"

RSpec.describe "Command-line interactive sessions" do
  around do |example|
    Dir.mktmpdir("jmespath-interactive") do |directory|
      @directory = directory
      example.run
    end
  end

  let(:path) { File.join(@directory, "document.json") }

  before { File.write(path, '{"name":"café","flag":false}', encoding: "UTF-8") }

  def run_cli(arguments = ["--interactive", "--file", path], input: StringIO.new("name\n:quit\n"))
    output = StringIO.new
    errors = StringIO.new
    status = JMESPath::CLI.run(arguments, stdin: input, stdout: output, stderr: errors)
    [status, output.string, errors.string]
  end

  def usage
    "Usage: jmespath [--pretty | --raw-output | --json-lines] [--file PATH] " \
      "(EXPRESSION | --query-file PATH)\n       " \
      "jmespath --validate (EXPRESSION | --query-file PATH)\n       jmespath --functions\n       " \
      "jmespath --interactive --file PATH\n" \
      "Use jmespath --help for options and topic help.\n"
  end

  it "supports option order, frozen arguments, and delimiter handling" do
    [["--interactive", "--file", path], ["--file", path, "--interactive"],
     ["--interactive", "--file=#{path}", "--"]].each do |arguments|
      original = arguments.dup
      expect(run_cli(arguments.freeze)).to eq([0, "\"café\"\n", ""])
      expect(arguments).to eq(original)
    end
  end

  it "opens the document once and closes it before reading commands" do
    input = double("query reader")
    opened = []
    expect(File).to receive(:open).once.and_wrap_original do |original, *arguments, &block|
      original.call(*arguments) do |file|
        opened << file
        block.call(file)
      end
    end
    expect(input).to receive(:gets).ordered do
      expect(opened.first).to be_closed
      File.write(path, '{"name":"changed"}')
      "name\n"
    end
    expect(input).to receive(:gets).ordered.and_return("name\n")
    expect(input).to receive(:gets).ordered.and_return(nil)
    expect(run_cli(input: input)).to eq([0, "\"café\"\n\"café\"\n", ""])
  end

  ["null", "false", "4", "[]", '"hello"'].each do |document|
    it "loads #{document} as a complete document" do
      File.write(path, document)
      expect(run_cli(input: StringIO.new("@\n"))).to eq([0, "#{document}\n", ""])
    end
  end

  it "supports literal paths under POSIXLY_CORRECT" do
    previous = ENV.fetch("POSIXLY_CORRECT", nil)
    ENV["POSIXLY_CORRECT"] = "1"
    ["my document.json", "--document.json", "-"].each do |filename|
      selected = File.join(@directory, filename)
      File.write(selected, "false")
      expect(run_cli(["--file=#{selected}", "--interactive"], input: StringIO.new("@\n")))
        .to eq([0, "false\n", ""])
    end
    Dir.chdir(@directory) do
      expect(run_cli(%w[--interactive --file -], input: StringIO.new("@\n"))).to eq([0, "false\n", ""])
    end
  ensure
    ENV["POSIXLY_CORRECT"] = previous
  end

  invalid = [%w[--interactive], %w[--interactive --file], %w[--interactive --file PATH @],
             %w[--interactive --file PATH --query-file QUERY], %w[--interactive --interactive --file PATH],
             %w[--interactive --file PATH --file PATH], %w[--inter --file PATH]]
  %w[--validate --pretty --raw-output --json-lines --functions --help --version].each do |flag|
    invalid << ["--interactive", "--file", "PATH", flag]
    invalid << [flag, "--file", "PATH", "--interactive"]
  end
  invalid.each do |arguments|
    it "rejects #{arguments.inspect} without touching files or stdin" do
      expect(File).not_to receive(:open)
      expect(run_cli(arguments, input: double("unused input"))).to eq([2, "", usage])
    end
  end

  it "keeps literal validation independent of interactive mode" do
    expect(File).not_to receive(:open)
    expect(run_cli(%w[--validate --interactive], input: double("unused input")).first).to eq(1)
  end

  it "reports missing documents and directories before reading commands" do
    [File.join(@directory, "missing"), @directory].each do |selected|
      status, output, errors = run_cli(["--interactive", "--file", selected], input: double("unused input"))
      expect([status, output]).to eq([1, ""])
      expect(errors).not_to be_empty
      expect(errors).not_to include("jmespath>")
    end
  end

  [Errno::EACCES, IOError].each do |type|
    it "reports #{type} during document startup" do
      allow(File).to receive(:open).with(path, "r:UTF-8").and_raise(type, "document failure")
      status, output, errors = run_cli(input: double("unused input"))
      expect([status, output]).to eq([1, ""])
      expect(errors).to include("document failure")
    end
  end

  it "reports malformed document JSON without private content or prompts" do
    File.write(path, '{"private_marker":BROKEN}')
    expect(run_cli(input: double("unused input"))).to eq([1, "", "Invalid JSON input\n"])
  end

  it "returns failure without retrying an unwritable startup diagnostic" do
    File.write(path, "BROKEN")
    errors = double("closed diagnostics")
    expect(errors).to receive(:puts).with("Invalid JSON input").once.and_raise(IOError, "closed diagnostics")
    status = JMESPath::CLI.run(["--interactive", "--file", path], stdin: double("unused input"),
                                                                  stdout: StringIO.new, stderr: errors)
    expect(status).to eq(1)
  end

  it "recovers when a valid query result exceeds JSON serialization nesting" do
    File.write(path, "#{'[' * 100}0#{']' * 100}")
    expect(run_cli(input: StringIO.new("[@]\n`1`\n:quit\n")))
      .to eq([0, "1\n", "Invalid JSON result\n"])
  end

  it "closes the document after a read failure before any command is consumed" do
    opened = []
    allow(File).to receive(:open).with(path, "r:UTF-8").and_wrap_original do |original, *arguments, &block|
      original.call(*arguments) do |file|
        opened << file
        allow(file).to receive(:read).and_raise(IOError, "read failed")
        block.call(file)
      end
    end
    expect(run_cli(input: double("unused input"))).to eq([1, "", "read failed\n"])
    expect(opened.first).to be_closed
  end

  it "documents interactive mode in help" do
    status, output, errors = run_cli(%w[--help interactive], input: double("unused input"))
    expect([status, errors]).to eq([0, ""])
    expect(output).to include("--interactive --file PATH", ":help", ":quit", "terminal")
  end

  %w[jmespath jmespath.rb].each do |name|
    def executable(name)
      [RbConfig.ruby, File.expand_path("../../exe/#{name}", __dir__), "--interactive", "--file", path]
    end

    it "recovers from query errors through #{name} with EOF and quit" do
      ["", ":quit\n"].each do |ending|
        queries = "items[\nlength(flag)\nlength()\nlenght(name)\n:help\nname\n#{ending}"
        output, errors, status = Open3.capture3(*executable(name), stdin_data: queries)
        expect([status.exitstatus, output]).to eq([0, "\"café\"\n"])
        expect(errors).to include("items[\n      ^", "received boolean", "received 0", "Did you mean length?", ":quit")
        expect(errors).not_to include("jmespath> ")
      end
    end

    it "routes inspection commands through #{name} without piped prompts" do
      queries = ":functions\n:explain name\n:trace missing\n:trace flag\n:quit\n"
      output, errors, status = Open3.capture3(*executable(name), stdin_data: queries)
      expect([status.exitstatus, output]).to eq([0, "null\nfalse\n"])
      expect(errors).to include("length(", "#0 field", "field_null", "Trace: no diagnostic events.")
      expect(errors).not_to include("jmespath> ", "Unknown command")
    end

    it "flushes results before receiving another piped query through #{name}" do
      Open3.popen3(*executable(name)) do |input, output, errors, waiter|
        Timeout.timeout(5) do
          input.puts("name")
          input.flush
          expect(output.gets).to eq("\"café\"\n")
          input.puts(":quit")
          input.flush
          expect(waiter.value.exitstatus).to eq(0)
          expect(errors.read).to eq("")
        end
      ensure
        if waiter.alive?
          Process.kill("KILL", waiter.pid)
          waiter.value
        end
      end
    end

    it "prompts with terminal stdin and redirected stderr through #{name}" do
      PTY.open do |master, slave|
        output, child_output = IO.pipe
        errors, child_errors = IO.pipe
        pid = Process.spawn(*executable(name), in: slave, out: child_output, err: child_errors)
        child_output.close
        child_errors.close
        Timeout.timeout(5) do
          expect(errors.read(10)).to eq("jmespath> ")
          master.puts("name")
          expect(output.gets).to eq("\"café\"\n")
          expect(errors.read(10)).to eq("jmespath> ")
          master.puts(":quit")
          expect(Process.wait2(pid).last.exitstatus).to eq(0)
          pid = nil
          expect(errors.read).to eq("")
        end
      ensure
        if pid
          Process.kill("KILL", pid)
          Process.wait(pid)
        end
        [output, errors, child_output, child_errors].compact.each { |stream| stream.close unless stream.closed? }
      end
    end

    it "reports startup failures through #{name}" do
      File.write(path, "BROKEN")
      output, errors, status = Open3.capture3(*executable(name), stdin_data: "name\n")
      expect([status.exitstatus, output, errors]).to eq([1, "", "Invalid JSON input\n"])
    end
  end
end
