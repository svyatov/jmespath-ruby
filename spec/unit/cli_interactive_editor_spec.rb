# frozen_string_literal: true

require "jmespath/cli"
require "stringio"
require "pty"
require "open3"
require "reline"

RSpec.describe "Interactive editor selection" do
  around do |example|
    previous = ENV.fetch("TERM", nil)
    ENV["TERM"] = "xterm-256color"
    example.run
  ensure
    ENV["TERM"] = previous
  end

  it "cancels an interrupted read without returning partial input" do
    errors = StringIO.new
    editor = JMESPath::CLI::InteractiveEditor.new(input: StringIO.new, errors: errors)
    expect(Reline).to receive(:readline).with("jmespath> ", false).ordered.and_raise(Interrupt)
    expect(Reline).to receive(:readline).with("jmespath> ", false).ordered.and_return("name")
    expect(editor.gets).to eq("name")
    expect(errors.string).to eq("^C\n")
  end

  it "runs a session through the editor without an extra prompt" do
    PTY.open do |_master, slave|
      output = StringIO.new
      allow(Reline).to receive(:readline).with("jmespath> ", false).and_return("name", nil)
      status = JMESPath::CLI::InteractiveSession.new({ "name" => "Ada" },
                                                     input: slave, output: output, errors: slave).run
      expect([status, output.string]).to eq([0, "\"Ada\"\n"])
    end
  end

  it "rejects injected readers even if they claim to be terminals" do
    input = StringIO.new
    allow(input).to receive(:tty?).and_return(true)
    expect(JMESPath::CLI::InteractiveEditor.supported?(input: input, errors: input)).to be(false)
    expect(JMESPath::CLI::InteractiveEditor.supported?(input: double("reader"), errors: input)).to be(false)
  end

  it "requires open terminal IO on both input and diagnostics" do
    PTY.open do |_master, slave|
      expect(JMESPath::CLI::InteractiveEditor.supported?(input: slave, errors: StringIO.new)).to be(false)
      expect(JMESPath::CLI::InteractiveEditor.supported?(input: StringIO.new, errors: slave)).to be(false)
      previous = ENV.fetch("TERM", nil)
      ENV["TERM"] = "dumb"
      expect(JMESPath::CLI::InteractiveEditor.supported?(input: slave, errors: slave)).to be(false)
      ENV["TERM"] = "xterm-256color"
      expect(JMESPath::CLI::InteractiveEditor.supported?(input: slave, errors: slave)).to be(true)
      slave.close
      expect(JMESPath::CLI::InteractiveEditor.supported?(input: slave, errors: slave)).to be(false)
    ensure
      ENV["TERM"] = previous
    end
  end

  it "rejects nonterminal IO without reading it" do
    File.open(File::NULL) do |input|
      expect(JMESPath::CLI::InteractiveEditor.supported?(input: input, errors: input)).to be(false)
    end
  end

  it "does not load Reline for library calls or piped sessions" do
    source = <<~RUBY
      require "jmespath/cli"
      require "stringio"
      JMESPath.search("@", {})
      JMESPath::CLI.run(["--version"], stdout: StringIO.new)
      JMESPath::CLI::InteractiveSession.new({}, input: StringIO.new("@\\n"),
        output: StringIO.new, errors: StringIO.new).run
      abort "Reline loaded" if $LOADED_FEATURES.any? { |path| path.include?("/reline") }
    RUBY
    output, errors, status = Open3.capture3(RbConfig.ruby, "-Ilib", "-e", source)
    expect([output, errors, status.exitstatus]).to eq(["", "", 0])
  end

  [nil, IOError, RuntimeError].each do |failure|
    it "restores Reline state after #{failure || 'normal exit'}" do
      original_input = Reline::IOGate.instance_variable_get(:@input)
      original_output = Reline.core.output
      original_config = Reline.core.config
      original_editor = Reline.core.line_editor
      callback = ->(_) { raise "external callback invoked" }
      Reline.completion_proc = callback
      original_history = Reline::HISTORY.to_a
      Reline::HISTORY.replace(["external query"])
      PTY.open do |_master, slave|
        editor = JMESPath::CLI::InteractiveEditor.new(input: slave, errors: slave)
        action = lambda do
          editor.open do
            expect(Reline::HISTORY).to be_empty
            expect(Reline.completion_proc).to be_nil
            expect(Reline.core.output).to equal(slave)
            raise failure, "failure" if failure
          end
        end
        failure ? expect(&action).to(raise_error(failure, "failure")) : action.call
        expect(slave).not_to be_closed
      end
      expect(Reline::IOGate.instance_variable_get(:@input)).to equal(original_input)
      expect(Reline.core.output).to equal(original_output)
      expect(Reline.core.config).to equal(original_config)
      expect(Reline.core.line_editor).to equal(original_editor)
      expect(Reline.completion_proc).to equal(callback)
      expect(Reline::HISTORY.to_a).to eq(["external query"])
    ensure
      Reline::HISTORY.replace(original_history)
      Reline.completion_proc = nil
    end
  end
end
