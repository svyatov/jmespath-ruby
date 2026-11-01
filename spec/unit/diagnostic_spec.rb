# frozen_string_literal: true

RSpec.describe "Syntax diagnostics" do
  def syntax_error(source, **options)
    JMESPath.compile(source, **options)
    raise "Expected invalid syntax"
  rescue JMESPath::Errors::SyntaxError => e
    e
  end

  {
    "items[?active" => "Expected rbracket, received eof at line 1, column 14\nitems[?active\n             ^",
    "foo = bar" => "Unexpected character at line 1, column 5\nfoo = bar\n    ^",
    "'unfinished" => "Unterminated quoted value at line 1, column 1\n'unfinished\n^",
    "" => "Expected an expression at line 1, column 1\n\n^",
    "foo\n$" => "Unexpected character at line 2, column 1\n$\n^",
    "foo.\n" => "Expected a field, function, or multiselect after dot at line 2, column 1\n\n^",
    "\t'✓' $" => "Unexpected character at line 1, column 6\n    '✓' $\n        ^",
    "a\t\t$" => "Unexpected character at line 1, column 4\na       $\n        ^",
    "'e\u0301界' $" => "Unexpected character at line 1, column 7\n'e\u0301界' $\n      ^",
    "'🙂' $" => "Unexpected character at line 1, column 5\n'🙂' $\n    ^",
    "foo\r\n$" => "Unexpected character at line 2, column 1\n$\n^",
    "foo\r$" => "Unexpected character at line 1, column 5\nfoo\\r$\n     ^"
  }.each do |source, expected|
    it "formats #{source.inspect}" do
      expect(JMESPath::Diagnostic.format(syntax_error(source))).to eq(expected)
    end
  end

  {
    "\0" => ["\\x00", "      ^"],
    "\e" => ["\\e", "    ^"],
    "\x7F" => ["\\x7F", "      ^"]
  }.each do |control, (escaped, caret)|
    it "escapes #{control.dump} before calculating caret indentation" do
      error = JMESPath::Errors::SyntaxError.new("Bad query", expression: "'#{control}'$", position: 3)
      expect(JMESPath::Diagnostic.format(error)).to eq("Bad query at line 1, column 4\n'#{escaped}'$\n#{caret}")
    end
  end

  it "calculates tab stops after visible control escapes" do
    error = JMESPath::Errors::SyntaxError.new("Bad query", expression: "\e\t$", position: 2)
    expect(JMESPath::Diagnostic.format(error)).to eq("Bad query at line 1, column 3\n\\e  $\n    ^")
  end

  [-1, 2, 3, 8].each do |offset|
    it "omits an unusable byte offset #{offset}" do
      error = JMESPath::Errors::SyntaxError.new("Bad query", expression: "'✓' $", position: offset)
      expect(JMESPath::Diagnostic.format(error)).to eq("Bad query")
    end
  end

  it "does not interpret an omitted position as the beginning of the query" do
    error = JMESPath::Errors::SyntaxError.new("Bad query", expression: "foo")
    expect(JMESPath::Diagnostic.format(error)).to eq("Bad query")
  end

  ["\xFF".b, "\xFF".b.force_encoding(Encoding::UTF_8)].each do |source|
    it "formats lexer errors for #{source.encoding} without inventing a location" do
      expect(JMESPath::Diagnostic.format(syntax_error(source))).to eq("Expression has invalid encoding")
    end

    it "omits unusable #{source.encoding} source even with an explicit position" do
      error = JMESPath::Errors::SyntaxError.new("Bad query", expression: source, position: 0)
      expect(JMESPath::Diagnostic.format(error)).to eq("Bad query")
    end
  end

  it "interprets offsets before converting a source to UTF-8" do
    source = "café $".encode(Encoding::ISO_8859_1)
    error = JMESPath::Errors::SyntaxError.new("Bad query", expression: source, position: 5)
    result = JMESPath::Diagnostic.format(error)
    expect(result).to eq("Bad query at line 1, column 6\ncafé $\n     ^")
    expect(result.encoding).to eq(Encoding::UTF_8)
    expect(error.expression.encoding).to eq(Encoding::ISO_8859_1)
  end

  it "rejects offsets within non-UTF-8 encoded characters" do
    error = JMESPath::Errors::SyntaxError.new("Bad query", expression: "界$".encode("UTF-16LE"), position: 1)
    expect(JMESPath::Diagnostic.format(error)).to eq("Bad query")
  end

  it "converts reason-only output to valid UTF-8" do
    error = JMESPath::Errors::SyntaxError.new("café".encode(Encoding::ISO_8859_1))
    result = JMESPath::Diagnostic.format(error)
    expect(result).to eq("café")
    expect(result.encoding).to eq(Encoding::UTF_8)
  end

  ["`\"\e\"`", "`{\n\e}`", "`\"\a\"`"].each do |source|
    it "escapes query controls embedded in the reason for #{source.dump}" do
      error = syntax_error(source)
      original = [error.reason, error.message]
      result = JMESPath::Diagnostic.format(error)
      expect(result).not_to include("\e", "\a")
      expect(result.lines.length).to eq(3)
      expect([error.reason, error.message]).to eq(original)
    end
  end

  it "escapes controls in reason-only output" do
    error = JMESPath::Errors::SyntaxError.new("Bad\nquery\e")
    expect(JMESPath::Diagnostic.format(error)).to eq("Bad\\nquery\\e")
    expect(error.reason).to eq("Bad\nquery\e")
  end

  it "locates parser nesting failures at the reported token" do
    error = syntax_error("((@))", max_depth: 1)
    expect(JMESPath::Diagnostic.format(error)).to eq("Expression exceeds nesting limit at line 1, column 3\n((@))\n  ^")
  end

  it "locates literal nesting failures at the opening quote" do
    error = syntax_error("`[[[0]]]`", max_depth: 1)
    expect(JMESPath::Diagnostic.format(error)).to eq(
      "Invalid quoted value: nesting of 2 is too deep at line 1, column 1\n`[[[0]]]`\n^"
    )
  end

  it "omits unknown locations on compiled-expression nesting failures" do
    query = JMESPath.compile("a[0][0]")
    expect { query.search({}, max_depth: 1) }.to raise_error(JMESPath::Errors::SyntaxError) { |error|
      expect(JMESPath::Diagnostic.format(error)).to eq("Expression exceeds nesting limit")
    }
  end

  it "preserves metadata and returns the same result across repeated calls" do
    source = +"'✓' $"
    error = syntax_error(source)
    source.replace("changed")
    2.times do
      expect(JMESPath::Diagnostic.format(error)).to eq("Unexpected character at line 1, column 5\n'✓' $\n    ^")
      expect([error.reason, error.message, error.expression, error.position, error.line, error.column]).to eq(
        ["Unexpected character", "Unexpected character at byte 6", "'✓' $", 6, 1, 5]
      )
    end
  end

  it "returns only query information without reading documents or printing output" do
    error = nil
    expect { JMESPath.search("query_marker[", { secret: "document_marker" }) }
      .to raise_error(JMESPath::Errors::SyntaxError) { |failure| error = failure }
    expect(JMESPath::Input).not_to receive(:load)
    expect(IO).not_to receive(:read)
    expect(File).not_to receive(:read)
    result = nil
    expect { result = JMESPath::Diagnostic.format(error) }.to output("").to_stdout.and output("").to_stderr
    expect(result).to include("query_marker[")
    expect(result).not_to include("document_marker")
  end
end
