# frozen_string_literal: true

RSpec.describe "Syntax validation" do
  %w[items[*].name unknown() length() length(`4`)].each do |source|
    it "accepts syntax without runtime checks for #{source}" do
      expect(JMESPath.validate(source)).to eq([])
      expect(JMESPath.validate(source)).to be_frozen
    end
  end

  {
    "items[?active" => ["Expected rbracket, received eof", 13, 1, 14],
    "" => ["Expected an expression", 0, 1, 1],
    "foo = bar" => ["Unexpected character", 4, 1, 5],
    "'unfinished" => ["Unterminated quoted value", 0, 1, 1],
    "foo\n$" => ["Unexpected character", 4, 2, 1],
    "foo.\n" => ["Expected a field, function, or multiselect after dot", 5, 2, 1],
    "\t'✓' $" => ["Unexpected character", 7, 1, 6],
    "'🙂' $" => ["Unexpected character", 7, 1, 5],
    "'e\u0301界' $" => ["Unexpected character", 9, 1, 7],
    "'\e' $" => ["Unexpected character", 4, 1, 5]
  }.each do |source, expected|
    it "returns the first located failure for #{source.inspect}" do
      result = JMESPath.validate(source)
      expect(result.length).to eq(1)
      expect(result).to be_frozen
      diagnostic = result.fetch(0)
      expect(diagnostic).to be_a(JMESPath::SyntaxDiagnostic)
      expect(diagnostic).to be_frozen
      expect(diagnostic.expression).to eq(source)
      expect([diagnostic.reason, diagnostic.position, diagnostic.line, diagnostic.column]).to eq(expected)
      expect(diagnostic.location_known?).to be(true)
    end
  end

  ["\xFF".b, "\xFF".b.force_encoding(Encoding::UTF_8)].each do |source|
    it "returns an unlocated failure for invalid #{source.encoding} input" do
      diagnostic = JMESPath.validate(source).fetch(0)
      expect(diagnostic.reason).to eq("Expression has invalid encoding")
      expect(diagnostic.expression).to eq("")
      expect([diagnostic.position, diagnostic.line, diagnostic.column]).to eq([nil, nil, nil])
      expect(diagnostic.location_known?).to be(false)
      expect(JMESPath::Diagnostic.format(diagnostic)).to eq("Expression has invalid encoding")
    end
  end

  it "owns deeply frozen copies without freezing caller input" do
    source = +"items[?active"
    result = JMESPath.validate(source)
    diagnostic = result.fetch(0)
    expect(source).not_to be_frozen
    source.clear
    expect(diagnostic.expression).to eq("items[?active")
    expect { result.clear }.to raise_error(FrozenError)
    expect { diagnostic.expression.clear }.to raise_error(FrozenError)
    expect { diagnostic.reason.clear }.to raise_error(FrozenError)
    expect(diagnostic).not_to be_a(Exception)
  end

  it "uses compilation coordinates after transcoding caller input" do
    source = "'café' $".encode(Encoding::ISO_8859_1)
    diagnostic = JMESPath.validate(source).fetch(0)
    expect(diagnostic.expression).to eq("'café' $")
    expect(diagnostic.expression.encoding).to eq(Encoding::UTF_8)
    expect([diagnostic.position, diagnostic.line, diagnostic.column]).to eq([8, 1, 8])
    expect(source.encoding).to eq(Encoding::ISO_8859_1)
    expect(source).not_to be_frozen
  end

  [1, 128].each do |depth|
    it "accepts a field at depth limit #{depth}" do
      expect(JMESPath.validate("@", max_depth: depth)).to eq([])
    end
  end

  it "reports expression and literal nesting failures" do
    expect(JMESPath.validate("((@))", max_depth: 1).fetch(0).reason).to eq("Expression exceeds nesting limit")
    expect(JMESPath.validate("`[[[0]]]`", max_depth: 1).fetch(0).position).to eq(0)
  end

  [nil, :query, 42].each do |source|
    it "rejects non-string input #{source.inspect}" do
      expect { JMESPath.validate(source) }.to raise_error(ArgumentError, "Expression must be a String")
    end
  end

  [nil, true, 0, 129, 1.0, "1"].each do |depth|
    it "rejects invalid depth #{depth.inspect} before parsing" do
      ["@", "items[", "\xFF".b].each do |source|
        expect { JMESPath.validate(source, max_depth: depth) }
          .to raise_error(ArgumentError, "max_depth must be an integer from 1 through 128")
      end
    end
  end

  %i[functions cache_expressions disable_visit_errors unknown].each do |keyword|
    it "rejects the unsupported #{keyword} keyword" do
      expect { JMESPath.validate("items[", **{ keyword => nil }) }.to raise_error(ArgumentError)
    end
  end

  it "never builds plans, accesses the cache, reads documents, or invokes functions" do
    registry = JMESPath::Functions.new.with("custom", signature: []) { raise "Callback executed" }
    expect(registry.names).to eq(["custom"])
    expect(JMESPath::Plan).not_to receive(:build)
    expect_any_instance_of(JMESPath::Cache).not_to receive(:fetch)
    expect_any_instance_of(JMESPath::Functions).not_to receive(:definition)
    expect_any_instance_of(JMESPath::Functions).not_to receive(:call)
    expect(JMESPath::Input).not_to receive(:load)
    expect { expect(JMESPath.validate("custom()")).to eq([]) }
      .to output("").to_stdout.and output("").to_stderr
  end

  it "propagates unrelated parser exceptions" do
    failure = RuntimeError.new("Parser defect")
    allow_any_instance_of(JMESPath::Parser).to receive(:parse).and_raise(failure)
    expect { JMESPath.validate("@") }.to(raise_error { |error| expect(error).to equal(failure) })
  end

  it "preserves the parser's zero slice step failure like compilation" do
    expect { JMESPath.validate("[::0]") }
      .to raise_error(JMESPath::Errors::InvalidValueError, "Slice step cannot be zero")
    expect { JMESPath.compile("[::0]", cache_expressions: false) }
      .to raise_error(JMESPath::Errors::InvalidValueError, "Slice step cannot be zero")
  end

  [
    ["@", 1], ["items[*].name", 128], ["unknown()", 128], ["length()", 128],
    ["", 128], ["items[?active", 128], ["((@))", 1], ["`[[[0]]]`", 1],
    ["\xFF".b, 128], ["\xFF".b.force_encoding(Encoding::UTF_8), 128],
    ["'café' $".encode(Encoding::ISO_8859_1), 128]
  ].each do |source, depth|
    it "agrees with uncached compilation for #{source.inspect} at depth #{depth}" do
      diagnostics = JMESPath.validate(source, max_depth: depth)
      begin
        JMESPath.compile(source, cache_expressions: false, max_depth: depth)
        expect(diagnostics).to eq([])
      rescue JMESPath::Errors::SyntaxError => e
        diagnostic = diagnostics.fetch(0)
        expect([diagnostic.reason, diagnostic.expression, diagnostic.location_known?])
          .to eq([e.reason, e.expression, e.location_known?])
        expected = e.location_known? ? [e.position, e.line, e.column] : [nil, nil, nil]
        expect([diagnostic.position, diagnostic.line, diagnostic.column]).to eq(expected)
      end
    end
  end
end
