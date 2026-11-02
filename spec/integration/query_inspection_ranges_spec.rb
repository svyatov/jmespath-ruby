# frozen_string_literal: true

RSpec.describe "Query inspection source ranges" do
  def ranges(node)
    [node.fetch(:source_range), *node.fetch(:children).flat_map { |child| ranges(child.fetch(:node)) }]
  end

  {
    "user.name" => [[0, 9], [0, 4], [5, 9]],
    "  user.name  " => [[2, 11], [2, 6], [7, 11]],
    "items[?active].name" => [[0, 19], [0, 5], [7, 13], [15, 19]],
    "[0]" => [[0, 3], nil],
    "items[*]" => [[0, 8], [0, 5], nil],
    "(@)" => [[0, 3], [1, 2]],
    '"café".name' => [[0, 12], [0, 7], [8, 12]],
    "\t\"café\".\r\n name\n" => [[1, 16], [1, 8], [12, 16]],
    "&name" => [[0, 5], [1, 5]],
    "!active" => [[0, 7], [1, 7]],
    "items[].name" => [[0, 12], [0, 7], [0, 5], [8, 12]],
    "items[1:5:2].name" => [[0, 17], [0, 12], [0, 5], [13, 17]],
    "{key: value}" => [[0, 12], [1, 11], [6, 11]],
    '"a\"b"' => [[0, 6]],
    "*" => [[0, 1], nil, nil],
    "[]" => [[0, 2], [0, 2], nil, nil],
    "[::]" => [[0, 4], [0, 4], nil, nil],
    "[?active]" => [[0, 9], nil, [2, 8], nil],
    "map(&name, items)" => [[0, 17], [4, 9], [5, 9], [11, 16]],
    "items[*].length(@)" => [[0, 18], [0, 5], [9, 18], [16, 17]]
  }.each do |source, expected|
    it "locates each logical operation in #{source.inspect}" do
      explanation = JMESPath.compile(source).explain
      expect(explanation.fetch(:source)).to eq(source)
      expect(ranges(explanation.fetch(:root))).to eq(expected)
      expected.compact.each do |start, finish|
        expect(start).to be >= 0
        expect(finish).to be <= explanation.fetch(:source).bytesize
        expect(explanation.fetch(:source).byteslice(start...finish)).to be_valid_encoding
      end
    end
  end

  it "extracts multiline Unicode expressions using exclusive UTF-8 byte ranges" do
    source = "\t\"café\".\r\n name\n"
    explanation = JMESPath.compile(source).explain
    fragments = ranges(explanation.fetch(:root)).map do |start, finish|
      explanation.fetch(:source).byteslice(start...finish)
    end
    expect(fragments).to eq(["\"café\".\r\n name", '"café"', "name"])
  end

  it "normalizes explanation coordinates without modifying the expression's source encoding" do
    source = "'café'".encode(Encoding::UTF_16LE)
    expression = JMESPath.compile(source)
    explanation = expression.explain
    expect(explanation.fetch(:source)).to eq("'café'")
    expect(explanation.fetch(:source).encoding).to eq(Encoding::UTF_8)
    expect(explanation.fetch(:root).fetch(:source_range)).to eq([0, 7])
    expect(explanation.fetch(:root).fetch(:details)).to eq(value: "café")
    expect(expression.source.encoding).to eq(Encoding::UTF_16LE)
    expect(expression.source.bytes).to eq(source.bytes)
  end
end
