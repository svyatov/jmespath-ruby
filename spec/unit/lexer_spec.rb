# frozen_string_literal: true

RSpec.describe "JMESPath lexical analysis" do
  def lex(source)
    JMESPath::Lexer.new(source).tokens
  end

  it "recognizes filter operators and field boundaries" do
    expect(lex("foo[?bar >= `2`].name").map(&:type)).to eq(
      %i[identifier filter identifier gte literal rbracket dot identifier eof]
    )
  end

  {
    "'café'" => [:literal, "café"],
    '"\\u2713"' => [:identifier, "✓"],
    "'don\\'t'" => [:literal, "don't"],
    "'a\\nb'" => [:literal, 'a\\nb'],
    "`{\"x\":[1,true,null]}`" => [:literal, { "x" => [1, true, nil] }],
    "`unquoted`" => [:literal, "unquoted"],
    "-12" => [:number, -12]
  }.each do |source, expected|
    it "decodes #{source.inspect}" do
      token = lex(source).first
      expect([token.type, token.value]).to eq(expected)
    end
  end

  it "recognizes every structural token" do
    expect(lex("[] [ ] { } ( ) , : . * @ & && | || ! != == < <= > >=").map(&:type)).to eq(
      %i[flatten lbracket rbracket lbrace rbrace lparen rparen comma colon dot star current
         expref and pipe or not ne eq lt lte gt gte eof]
    )
  end

  it "keeps byte positions while reporting character columns" do
    expect { lex("'✓' $") }.to raise_error(JMESPath::Errors::SyntaxError) { |error|
      expect(error.position).to eq(6)
      expect(error.line).to eq(1)
      expect(error.column).to eq(5)
    }
  end

  it "reports unterminated strings" do
    expect { lex("'unfinished") }.to raise_error(JMESPath::Errors::SyntaxError)
  end

  it "rejects malformed encoded input" do
    expect { lex("\xFF".b) }.to raise_error(JMESPath::Errors::SyntaxError)
  end

  it "rejects invalid JSON escapes in quoted identifiers" do
    expect { lex('"\x"') }.to raise_error(JMESPath::Errors::SyntaxError)
  end

  it "rejects a minus without digits" do
    expect { lex("-") }.to raise_error(JMESPath::Errors::SyntaxError)
  end

  it "reports a position after a newline" do
    expect { lex("foo\n$") }.to raise_error(JMESPath::Errors::SyntaxError) { |error|
      expect([error.line, error.column, error.position]).to eq([2, 1, 4])
    }
  end

  it "preserves the source string" do
    source = +"foo"
    lex(source)
    expect(source).not_to be_frozen
    expect(source).to eq("foo")
  end
end
