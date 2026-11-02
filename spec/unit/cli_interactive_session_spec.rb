# frozen_string_literal: true

require "stringio"
require "jmespath/cli"

RSpec.describe "Interactive query session" do
  let(:data) { { "name" => "café", "flag" => false } }

  def session(text = "", input: StringIO.new(text), output: StringIO.new, errors: StringIO.new)
    status = JMESPath::CLI::InteractiveSession.new(data, input: input, output: output, errors: errors).run
    [status, output.string, errors.string]
  end

  it "evaluates successive queries including missing and false values" do
    expect(session("name\nmissing\nflag\n")).to eq([0, "\"café\"\nnull\nfalse\n", ""])
    expect(session("\n \t\r\nname\r\nflag")).to eq([0, "\"café\"\nfalse\n", ""])
    expect(session("  :quit\t\nname\n")).to eq([0, "", ""])
  end

  it "explains commands and recovers from unknown commands and malformed UTF-8" do
    status, output, errors = session(":help\n:bad\e\n\xFF\nname\n".b)
    expect([status, output]).to eq([0, "\"café\"\n"])
    expect(errors).to include(":help", ":quit", "one query per line", "blank", "Unknown command", "\\e",
                              "Invalid UTF-8 query")
    expect(errors).not_to include("\e")
  end

  {
    "items[" => "Expected an array index at line 1, column 7\nitems[\n      ^\n",
    "length(flag)" => "Invalid argument 1 for length: expected string, array, or object; received boolean " \
                      "at line 1, column 1\nlength(flag)\n^\n",
    "  length()" => "Invalid number of arguments for length: expected 1; received 0 " \
                    "at line 1, column 3\n  length()\n  ^\n",
    "['✓', length()]" => "Invalid number of arguments for length: expected 1; received 0 " \
                         "at line 1, column 7\n['✓', length()]\n      ^\n",
    "lenght(name)" => "Unknown function: lenght. Did you mean length?\n"
  }.each do |query, diagnostic|
    ["", ":quit\n"].each do |ending|
      it "recovers from #{query.inspect} before #{ending.empty? ? 'EOF' : ':quit'}" do
        expect(session("#{query}\nname\n#{ending}")).to eq([0, "\"café\"\n", diagnostic])
      end
    end
  end

  it "recovers from serialization failures" do
    allow(JSON).to receive(:generate).and_call_original
    allow(JSON).to receive(:generate).with(false).and_raise(JSON::GeneratorError, "private")
    expect(session("flag\nname\n")).to eq([0, "\"café\"\n", "Invalid JSON result\n"])
  end

  [RuntimeError, ArgumentError].each do |type|
    it "propagates unrelated #{type}" do
      allow(JMESPath).to receive(:search).and_raise(type, "unexpected")
      expect { session("name\n") }.to raise_error(type, "unexpected")
    end
  end

  it "reads incrementally, flushes results, and stops without reading beyond quit" do
    input = double("gets-only reader")
    output = StringIO.new
    expect(input).to receive(:gets).ordered.and_return("name\n")
    expect(output).to receive(:puts).with('"café"').ordered.and_call_original
    expect(output).to receive(:flush).ordered.and_call_original
    expect(input).to receive(:gets).ordered.and_return(":quit\n")
    expect(session(input: input, output: output)).to eq([0, "\"café\"\n", ""])
    expect(output).not_to be_closed
  end

  it "supports puts-only writers without optional flushing" do
    output = double("puts-only output")
    errors = double("puts-only errors")
    expect(output).to receive(:puts).with('"café"')
    expect(errors).to receive(:puts).with("Unknown command: :bad")
    status = JMESPath::CLI::InteractiveSession.new(data, input: StringIO.new(":bad\nname\n"),
                                                         output: output, errors: errors).run
    expect(status).to eq(0)
  end

  it "prompts and flushes before every terminal read on the diagnostic stream" do
    input = StringIO.new
    errors = StringIO.new
    allow(input).to receive(:tty?).and_return(true)
    expect(errors).to receive(:print).with("jmespath> ").ordered.and_call_original
    expect(errors).to receive(:flush).ordered.and_call_original
    expect(input).to receive(:gets).ordered.and_return("name\n")
    expect(errors).to receive(:print).with("jmespath> ").ordered.and_call_original
    expect(errors).to receive(:flush).ordered.and_call_original
    expect(input).to receive(:gets).ordered.and_return(nil)
    expect(session(input: input, errors: errors)).to eq([0, "\"café\"\n", "jmespath> jmespath> "])
    expect(input).not_to be_closed
    expect(errors).not_to be_closed
  end

  [IOError, Errno::EIO].each do |type|
    %i[gets puts flush].each do |method|
      it "terminates after #{type} from #{method}" do
        input = StringIO.new("name\nflag\n")
        output = StringIO.new
        target = method == :gets ? input : output
        allow(target).to receive(method).and_raise(type, "failure")
        status, = session(input: input, output: output)
        expect(status).to eq(1)
        expect(input).not_to be_closed
      end
    end
  end

  it "retains earlier output when later input fails" do
    input = double("failing reader")
    expect(input).to receive(:gets).ordered.and_return("name\n")
    expect(input).to receive(:gets).ordered.and_raise(IOError, "read failed")
    expect(session(input: input)).to eq([1, "\"café\"\n", "read failed\n"])
  end

  it "returns failure when reporting an input failure also fails" do
    input = double("closed input")
    errors = StringIO.new
    expect(input).to receive(:gets).and_raise(IOError, "closed input")
    expect(errors).to receive(:puts).once.and_raise(IOError, "closed diagnostics")
    expect(session(input: input, errors: errors)).to eq([1, "", ""])
  end

  it "terminates without consuming input when a terminal prompt cannot flush" do
    input = StringIO.new("name\n")
    errors = StringIO.new
    allow(input).to receive(:tty?).and_return(true)
    expect(errors).to receive(:flush).once.and_raise(Errno::EIO)
    expect(session(input: input, errors: errors)).to eq([1, "", "jmespath> "])
    expect(input.pos).to eq(0)
  end

  %i[puts flush print].each do |method|
    it "does not retry a failed diagnostic #{method}" do
      input = StringIO.new("items[\nname\n")
      errors = StringIO.new
      allow(input).to receive(:tty?).and_return(method == :print)
      expect(errors).to receive(method).once.and_raise(IOError, "closed diagnostics")
      expect(session(input: input, errors: errors).first).to eq(1)
      expect(input.pos).to be < input.size
    end
  end
end
