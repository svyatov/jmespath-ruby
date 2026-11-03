# frozen_string_literal: true

require "stringio"
require "jmespath/cli"

RSpec.describe "Interactive query session" do
  let(:data) { { "name" => "café", "flag" => false } }

  def session(text = "", input: StringIO.new(text), output: StringIO.new, errors: StringIO.new, document: data)
    status = JMESPath::CLI::InteractiveSession.new(document, input: input, output: output, errors: errors).run
    [status, output.string, errors.string]
  end

  it "evaluates successive queries including missing and false values" do
    expect(session("name\nmissing\nflag\n")).to eq([0, "\"café\"\nnull\nfalse\n", ""])
    expect(session("\n \t\r\nname\r\nflag")).to eq([0, "\"café\"\nfalse\n", ""])
    expect(session("  :quit\t\nname\n")).to eq([0, "", ""])
  end

  it "lists built-in signatures and descriptions only on stderr" do
    status, output, errors = session(":functions\n")
    expect([status, output]).to eq([0, ""])
    expect(errors).to include("length(", "Types: any accepts any value", "expref", "Signatures describe")
  end

  it "explains the complete query remainder without evaluating the document" do
    expect(JMESPath).to receive(:compile).with("unknown(name) \t").once.and_call_original
    expect(JMESPath).not_to receive(:search)
    expect(data).not_to receive(:[])
    status, output, errors = session(" \t:explain \t unknown(name) \t\n")
    expect([status, output]).to eq([0, ""])
    expect(errors).to include("function", 'name="unknown"', "line 1, column 1")
    expect(errors).not_to include("Unknown function")
  end

  [":explain", ":explain \t", ":functions extra", ":explainx name", ":quit extra", ":help extra"].each do |command|
    it "recovers from invalid command #{command.inspect}" do
      status, output, errors = session("#{command}\nname\n:quit\n")
      expect([status, output]).to eq([0, "\"café\"\n"])
      expect(errors).not_to be_empty
    end
  end

  it "recovers from invalid explanation syntax" do
    status, output, errors = session(":explain items[\nname\n")
    expect([status, output]).to eq([0, "\"café\"\n"])
    expect(errors).to include("items[\n      ^")
  end

  it "traces once and writes one JSON result with ordered omission diagnostics" do
    document = { "items" => [{ "name" => "Ada" }, {}, { "name" => false }] }
    expect(JMESPath).to receive(:compile).with("items[*].name").once.and_call_original
    expect(JMESPath).not_to receive(:search)
    calls = 0
    observer = TracePoint.new(:call) do |event|
      calls += 1 if event.defined_class == JMESPath::Expression && event.method_id == :trace
    end
    status, output, errors = observer.enable { session(":trace items[*].name\n", document: document) }
    expect(calls).to eq(1)
    expect([status, output]).to eq([0, "[\"Ada\",false]\n"])
    expect(errors.lines.map { |line| line.split.first }).to eq(%w[field_null projection_omission])
    expect(errors).to include('name="name" reason="missing"', "context=[#0 index=1]")
  end

  it "retains null and false trace results and reports an empty trace" do
    status, output, errors = session(":trace missing\n:trace flag\n")
    expect([status, output]).to eq([0, "null\nfalse\n"])
    expect(errors).to include("field_null", "Trace: no diagnostic events.")
  end

  it "limits diagnostic events while completing the full evaluation" do
    document = { "items" => Array.new(1001) { {} } + [{ "name" => "last" }] }
    status, output, errors = session(":trace items[*].name\n", document: document)
    expect([status, output]).to eq([0, "[\"last\"]\n"])
    expect(errors.lines.count { |line| line.match?(/\A(?:field_null|projection_omission) /) }).to eq(1000)
    expect(errors).to include("first 1000 events", "evaluation completed")
  end

  it "recovers from all supported trace failures before an ordinary query" do
    text = ":trace\n:trace items[\n:trace length(flag)\n:trace length()\n:trace lenght(name)\nname\n"
    status, output, errors = session(text)
    expect([status, output]).to eq([0, "\"café\"\n"])
    expect(errors).to include(":trace requires a query", "items[\n      ^", "received boolean", "received 0",
                              "Did you mean length?")
  end

  ["`1e999`", "#{'[' * 101}flag#{']' * 101}"].each do |query|
    it "serializes #{query.inspect} before writing a trace report" do
      status, output, errors = session(":trace #{query}\nname\n")
      expect([status, output, errors]).to eq([0, "\"café\"\n", "Invalid JSON result\n"])
    end
  end

  %i[puts flush].each do |method|
    it "terminates without a result or repeated write after trace report #{method} fails" do
      input = StringIO.new(":trace flag\nname\n")
      errors = StringIO.new
      expect(errors).to receive(method).once.and_raise(IOError, "report failed")
      status, output, = session(input: input, errors: errors)
      expect([status, output, input.gets]).to eq([1, "", "name\n"])
    end
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
