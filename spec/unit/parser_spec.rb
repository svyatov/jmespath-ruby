# frozen_string_literal: true

RSpec.describe "JMESPath grammar" do
  def parse(source, **options)
    JMESPath::Parser.new(source, **options).parse
  end

  it "binds conjunction more tightly than disjunction" do
    node = parse("a || b && c")
    expect(node.kind).to eq(:or)
    expect(node.children.last.kind).to eq(:and)
  end

  it "keeps pipe outside projection" do
    expect(parse("items[?ok].name | [0]").kind).to eq(:pipe)
  end

  it "parses function expression references" do
    expect(parse("sort_by(items, &name)").children.last.kind).to eq(:expression_reference)
  end

  it "rejects zero slice steps" do
    expect { parse("items[1:2:0]") }.to raise_error(JMESPath::Errors::InvalidValueError)
  end

  it "rejects excessive nesting before exhausting the Ruby stack" do
    expect { parse("#{'(' * 129}@#{')' * 129}") }.to raise_error(JMESPath::Errors::SyntaxError)
    expect(parse("#{'(' * 128}@#{')' * 128}").depth).to eq(128)
  end

  it "keeps long field chains shallow" do
    node = parse(Array.new(2_000, "a").join("."))
    expect(node.kind).to eq(:subexpression)
    expect(node.children.length).to eq(2_000)
    expect(node.depth).to eq(1)
  end

  it "deeply freezes literal templates" do
    node = parse("'x'")
    expect(node).to be_frozen
    expect(node.value).to be_frozen
    expect(node.children).to be_frozen
  end

  [
    "@", "*", "foo.*.bar", "foo[*].bar", "foo[]", "[]", "foo[1]", "[-1]",
    "[::]", "foo[::-1]", "[a,b]", "{x:a,y:b}", "(a)", "!foo", "a == b",
    "a != b", "a < b", "a <= b", "a > b", "a >= b", "foo()", "foo(a,b)",
    "foo[?x && y]", "foo.[a,b]", 'foo."space key"'
  ].each do |source|
    it("accepts #{source.inspect}") { expect(parse(source)).to be_a(JMESPath::AST::Node) }
  end

  ["", "a.", "a[", "[]]", "{x:}", "a b", "[a,]", "foo(a,)", '"foo"()', "a.@"].each do |source|
    it("rejects #{source.inspect}") { expect { parse(source) }.to raise_error(JMESPath::Errors::SyntaxError) }
  end
end
