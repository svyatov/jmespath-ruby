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

  it "returns all confirmed pasted lines without another terminal read" do
    editor = JMESPath::CLI::InteractiveEditor.new(input: StringIO.new, errors: StringIO.new)
    allow(Reline).to receive(:readline).with("jmespath> ", false).and_return("flag", nil)
    allow(Reline.core.line_editor).to receive(:whole_lines).and_return(%w[name flag])
    expect(editor.gets).to eq("name")
    expect(editor.gets).to eq("flag")
    expect(editor.gets).to be_nil
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

  it "does not retry terminal output after an editor write fails" do
    PTY.open do |_master, slave|
      allow(Reline).to receive(:readline) { Reline.core.output.write("jmespath> ") }
      expect(slave).to receive(:write).once.and_raise(IOError, "terminal failed")
      expect(slave).not_to receive(:puts)
      status = JMESPath::CLI::InteractiveSession.new({}, input: slave, output: StringIO.new, errors: slave).run
      expect(status).to eq(1)
    end
  end

  [13, 4].each do |byte|
    it "handles an invalid sequence ending with byte #{byte} without consuming the next line" do
      errors = StringIO.new
      editor = JMESPath::CLI::InteractiveEditor.new(input: StringIO.new, errors: errors)
      error = JMESPath::CLI::InteractiveKeyStroke::InvalidInput.new(byte)
      allow(Reline).to receive(:readline).and_raise(error)
      expect(Reline::IOGate).not_to receive(:getc)
      line = editor.gets
      valid = line && line.dup.force_encoding(Encoding::UTF_8).valid_encoding?
      expect(valid).to eq(byte == 4 ? nil : false)
      expect(errors.string).to eq("\n")
    end
  end

  [nil, 4, 13].each do |terminator|
    it "discards an invalid edit through terminal terminator #{terminator.inspect}" do
      PTY.open do |_master, slave|
        editor = JMESPath::CLI::InteractiveEditor.new(input: slave, errors: StringIO.new)
        error = JMESPath::CLI::InteractiveKeyStroke::InvalidInput.new(255)
        allow(Reline).to receive(:readline).and_raise(error)
        allow(Reline::IOGate).to receive(:getc).with(Float::INFINITY).and_return(65, terminator)
        editor.open do
          line = editor.gets
          valid = line && line.dup.force_encoding(Encoding::UTF_8).valid_encoding?
          expect(valid).to eq(terminator == 13 ? false : nil)
        end
      end
    end
  end

  it "cancels a discarded invalid edit on interrupt" do
    PTY.open do |_master, slave|
      errors = StringIO.new
      editor = JMESPath::CLI::InteractiveEditor.new(input: slave, errors: errors)
      error = JMESPath::CLI::InteractiveKeyStroke::InvalidInput.new(255)
      expect(Reline).to receive(:readline).ordered.and_raise(error)
      expect(Reline).to receive(:readline).ordered.and_return("name")
      allow(Reline::IOGate).to receive(:getc).and_raise(Interrupt)
      editor.open { expect(editor.gets).to eq("name") }
      expect(errors.string).to eq("^C\n")
    end
  end

  [["lengzz(name)", 4, "length(name)", 6, ""],
   ["to_", 3, "to_", 3, "to_array  to_number  to_string\n"],
   ["zzzz", 4, "zzzz", 4, ""]].each do |line, point, expected, cursor, diagnostic|
    it "applies the terminal completion callback to #{line}" do
      PTY.open do |_master, slave|
        errors = StringIO.new
        editor = JMESPath::CLI::InteractiveEditor.new(input: slave, errors: errors)
        editor.open do
          allow(Reline.core.line_editor).to receive(:render_finished)
          Reline.insert_text(line)
          Reline.point = point
          expect(Reline.completion_proc.call("")).to be_nil
          expect([Reline.line_buffer, Reline.point, errors.string]).to eq([expected, cursor, diagnostic])
        end
      end
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

  it "falls back when Reline has an unsupported terminal backend" do
    PTY.open do |_master, slave|
      backend = double("dumb backend", dumb?: true)
      stub_const("Reline::IOGate", backend)
      expect(JMESPath::CLI::InteractiveEditor.supported?(input: slave, errors: slave)).to be(false)
      allow(backend).to receive(:dumb?).and_return(false)
      expect(JMESPath::CLI::InteractiveEditor.supported?(input: slave, errors: slave)).to be(false)
      allow(backend).to receive(:input=)
      expect(JMESPath::CLI::InteractiveEditor.supported?(input: slave, errors: slave)).to be(false)
    end
  end

  it "retains 500 queries in submission order including duplicates" do
    PTY.open do |_master, slave|
      editor = JMESPath::CLI::InteractiveEditor.new(input: slave, errors: slave)
      editor.open do
        501.times { |index| editor.remember("q#{index}") }
        expect(Reline::HISTORY.size).to eq(500)
        expect(Reline::HISTORY.first).to eq("q1")
        expect(Reline::HISTORY.last).to eq("q500")
        editor.remember("q500")
        expect(Reline::HISTORY.last(2)).to eq(%w[q500 q500])
      end
    end
  end

  it "records failed queries and excludes commands and malformed input" do
    PTY.open do |_master, slave|
      output = StringIO.new
      lines = ["\n", " \t\r\n", "\xFF".b, ":help", ":bad", "  name\r\n", "items[", "name", nil]
      allow(Reline).to receive(:readline).and_return(*lines)
      history = nil
      allow(JMESPath).to receive(:search).and_wrap_original do |original, expression, data|
        history = Reline::HISTORY.to_a
        original.call(expression, data)
      end
      status = JMESPath::CLI::InteractiveSession.new({ "name" => "Ada" },
                                                     input: slave, output: output, errors: slave).run
      expect(status).to eq(0)
      expect(history).to eq(["  name", "items[", "name"])
      expect(output.string).to eq("\"Ada\"\n\"Ada\"\n")
    end
  end

  it "isolates session history from external history settings" do
    config = Reline.core.config
    previous_size = config.history_size
    previous_history = Reline::HISTORY.to_a
    config.history_size = 0
    Reline::HISTORY.replace(["external"])
    PTY.open do |_master, slave|
      2.times do
        editor = JMESPath::CLI::InteractiveEditor.new(input: slave, errors: slave)
        editor.open do
          expect(Reline::HISTORY).to be_empty
          editor.remember("name")
          expect(Reline::HISTORY.to_a).to eq(["name"])
        end
        expect(Reline::HISTORY.to_a).to eq(["external"])
      end
    end
  ensure
    config.history_size = previous_size
    Reline::HISTORY.replace(previous_history)
  end

  it "allows recall beyond a caller's smaller history limit" do
    config = Reline.core.config
    previous_size = config.history_size
    config.history_size = 2
    PTY.open do |_master, slave|
      editor = JMESPath::CLI::InteractiveEditor.new(input: slave, errors: slave)
      editor.open do
        5.times { |index| editor.remember("q#{index}") }
        expect(Reline::HISTORY[4]).to eq("q4")
      end
    end
    expect(config.history_size).to eq(2)
  ensure
    config.history_size = previous_size
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
            expect(Reline.completion_proc).not_to equal(callback)
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
