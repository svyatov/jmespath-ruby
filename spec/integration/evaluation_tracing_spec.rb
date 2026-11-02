# frozen_string_literal: true

require "tempfile"

RSpec.describe "Traced evaluation" do
  it "returns the exact report for an absent field" do
    expect(JMESPath.compile("x").trace({})).to eq(
      value: nil, events: [
        { type: "field_null", operation_id: 0, context: [], details: { name: "x", reason: "missing" } }
      ], truncated: false
    )
  end

  it "preserves selected values and ordinary mutability" do
    [false, 0, "", [], {}].each do |value|
      report = JMESPath.compile("x").trace({ x: value })
      expect(report[:value]).to equal(value)
      expect(report[:events]).to eq([])
      expect(value).not_to be_frozen if value.is_a?(Array) || value.is_a?(Hash)
    end
    literal = JMESPath.compile("'text'").trace(nil)[:value]
    literal << "!"
    expect(literal).to eq("text!")
  end

  it "requires a positive integer limit before consuming input" do
    reader = StringIO.new("{}")
    [0, -1, 1.0, nil, true].each do |limit|
      expect { JMESPath.compile("x").trace(reader, limit: limit) }.to raise_error(ArgumentError)
      expect(reader.pos).to eq(0)
    end
  end

  it "rejects invalid evaluation options before reading input" do
    query = JMESPath.compile("x")
    reader = StringIO.new("{}")
    [
      -> { query.trace(reader, { limit: 1 }) },
      -> { query.trace(reader, nope: true) },
      -> { query.trace(reader, { max_depth: 2 }, max_depth: 3) },
      -> { query.trace(reader, nil) }
    ].each do |call|
      expect(&call).to raise_error(ArgumentError)
      expect(reader.pos).to eq(0)
    end
  end

  it "uses saved options and per-call overrides" do
    first = JMESPath::Functions.default.with("answer", signature: []) { 7 }
    second = JMESPath::Functions.default.with("answer", signature: []) { false }
    query = JMESPath.compile("answer()", functions: first, disable_visit_errors: true)
    expect(query.trace(nil)[:value]).to eq(7)
    expect(query.trace(nil, functions: second)[:value]).to be(false)
    expect(JMESPath.compile("length(@)", disable_visit_errors: true).trace(4)[:value]).to be_nil
    expect { JMESPath.compile("length(@)", disable_visit_errors: true).trace(4, disable_visit_errors: false) }
      .to raise_error(JMESPath::Errors::InvalidTypeError)
  end

  it "loads streams and files once with ordinary search semantics" do
    reader = StringIO.new('{"x":7}')
    expect(JMESPath.compile("x").trace(reader)[:value]).to eq(7)
    expect(reader.pos).to eq(reader.size)
    Tempfile.create("tracing") do |file|
      file.write('{"x":false}')
      file.flush
      expect(JMESPath.compile("x").trace(Pathname.new(file.path))[:value]).to be(false)
    end
  end

  it "preserves per-call depth limits and input errors" do
    query = JMESPath.compile("((x))")
    expect { query.trace({}, max_depth: 1) }.to raise_error(JMESPath::Errors::SyntaxError)
    expect { query.trace(StringIO.new("{")) }.to raise_error(JSON::ParserError)
    reader = StringIO.new("{}")
    reader.close
    expect { query.trace(reader) }.to raise_error(IOError)
  end
end
