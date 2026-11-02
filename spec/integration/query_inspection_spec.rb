# frozen_string_literal: true

RSpec.describe "Compiled query inspection" do
  def nodes(node)
    [node, *node.fetch(:children).flat_map { |child| nodes(child.fetch(:node)) }]
  end

  def expect_frozen(value)
    expect(value).to be_frozen
    case value
    when Hash
      value.each do |key, entry|
        expect_frozen(key)
        expect_frozen(entry)
      end
    when Array then value.each { |entry| expect_frozen(entry) }
    end
  end

  let(:field_chain) do
    {
      source: "user.name",
      root: {
        id: 0, operation: "subexpression", source_range: [0, 9], details: {},
        children: [
          { role: "step", node: {
            id: 1, operation: "field", source_range: [0, 4], details: { name: "user" }, children: []
          } },
          { role: "step", node: {
            id: 2, operation: "field", source_range: [5, 9], details: { name: "name" }, children: []
          } }
        ]
      }
    }
  end

  it "returns the public logical tree with source text and preorder IDs" do
    expect(JMESPath.compile("user.name").explain).to eq(field_chain)
  end

  {
    "name" => ["field", { name: "name" }, []],
    '"a\"b"' => ["field", { name: 'a"b' }, []],
    "@" => ["current", {}, []],
    "'hello'" => ["literal", { value: "hello" }, []],
    "`{\"key\":[1,true,null]}`" => ["literal", { value: { "key" => [1, true, nil] } }, []],
    "(@)" => ["group", {}, ["expression"]],
    "a.b.c" => ["subexpression", {}, %w[step step step]],
    "a | b | c" => ["pipe", {}, %w[step step step]],
    "a[-1]" => ["index", { index: -1 }, ["input"]],
    "items[*].name" => ["projection", {}, %w[input expression]],
    "items.*.name" => ["value_projection", {}, %w[input expression]],
    "items[?active].name" => ["filter_projection", {}, %w[input condition expression]],
    "&name" => ["expression_reference", {}, ["expression"]],
    "unknown(a, &b)" => ["function", { name: "unknown" }, %w[argument argument]],
    "unknown()" => ["function", { name: "unknown" }, []],
    "a && b && c" => ["and", {}, %w[operand operand operand]],
    "a || b || c" => ["or", {}, %w[operand operand operand]],
    "!active" => ["not", {}, ["operand"]],
    "[a,b]" => ["multi_select_list", {}, %w[element element]],
    "{x:a,x:b}" => ["multi_select_hash", {}, %w[entry entry]]
  }.each do |source, (operation, details, roles)|
    it "explains #{source} using public operation names and child roles" do
      root = JMESPath.compile(source).explain.fetch(:root)
      expect(root.fetch(:operation)).to eq(operation)
      expect(root.fetch(:details)).to eq(details)
      expect(root.fetch(:children).map { |child| child.fetch(:role) }).to eq(roles)
    end
  end

  %w[== != < <= > >=].each do |operator|
    it "explains the #{operator} comparison" do
      root = JMESPath.compile("a #{operator} b").explain.fetch(:root)
      expect(root.fetch(:operation)).to eq("comparison")
      expect(root.fetch(:details)).to eq(operator: operator)
      expect(root.fetch(:children).map { |child| child.fetch(:role) }).to eq(%w[left right])
    end
  end

  { "items[1:5:2]" => [1, 5, 2], "items[::-1]" => [nil, nil, -1], "[::]" => [nil, nil, nil] }
    .each do |source, (start, stop, step)|
    it "preserves omitted slice components in #{source}" do
      root = JMESPath.compile(source).explain.fetch(:root)
      slice = root.fetch(:children).first.fetch(:node)
      expect(slice.fetch(:operation)).to eq("slice")
      expect(slice.fetch(:details)).to eq(start: start, stop: stop, step: step)
      expect(slice.fetch(:children).first.fetch(:role)).to eq("input")
    end
  end

  it "orders filter children semantically before numbering the complete tree" do
    root = JMESPath.compile("items[?active].name | sort(@)").explain.fetch(:root)
    expect(nodes(root).map { |node| node.fetch(:id) }).to eq((0..6).to_a)
    expect(nodes(root).map { |node| node.fetch(:operation) })
      .to eq(%w[pipe filter_projection field field field function current])
    filter = root.fetch(:children).first.fetch(:node)
    expect(filter.fetch(:children).map { |child| child.fetch(:node).fetch(:details) })
      .to eq([{ name: "items" }, { name: "active" }, { name: "name" }])
  end

  it "preserves flattening and repeated hash entries" do
    flatten = nodes(JMESPath.compile("items[].name").explain.fetch(:root)).fetch(1)
    expect(flatten.values_at(:operation, :details)).to eq(["flatten", {}])
    expect(flatten.fetch(:children).first.fetch(:role)).to eq("input")
    entries = JMESPath.compile("{x:a,x:b}").explain.fetch(:root).fetch(:children).map { |child| child.fetch(:node) }
    expect(entries.map { |entry| entry.values_at(:operation, :details) }).to eq([["entry", { name: "x" }]] * 2)
    expect(entries.map { |entry| entry.fetch(:children).first.fetch(:role) }).to eq(%w[expression expression])
    expect(entries.map { |entry| entry.fetch(:children).first.fetch(:node).fetch(:details) })
      .to eq([{ name: "a" }, { name: "b" }])
  end

  it "inspects long flat chains and maximum-depth groups" do
    root = JMESPath.compile(Array.new(2_000, "a").join(".")).explain.fetch(:root)
    expect(root.fetch(:children).length).to eq(2_000)
    expect(root.fetch(:children).map { |child| child.fetch(:role) }.uniq).to eq(["step"])
    expect(nodes(root).map { |node| node.fetch(:id) }).to eq((0..2_000).to_a)
    nested = JMESPath.compile("#{'(' * 128}@#{')' * 128}").explain.fetch(:root)
    expect(nodes(nested).length).to eq(129)
  end

  it "deeply freezes literal values without freezing search results" do
    expression = JMESPath.compile('`{"key":["value",1,true,false,null]}`')
    explanation = expression.explain
    expect_frozen(explanation)
    literal = explanation.fetch(:root).fetch(:details).fetch(:value)
    expect { literal.fetch("key") << "other" }.to raise_error(FrozenError)
    expect { literal.fetch("key").first.replace("other") }.to raise_error(FrozenError)
    value = expression.search(nil)
    value.fetch("key") << "other"
    expect(expression.explain).to eq(explanation)
    expect(expression.search(nil)).to eq("key" => ["value", 1, true, false, nil])
  end

  it "serializes directly to JSON including nil source ranges" do
    result = JSON.parse(JSON.generate(JMESPath.compile("[0]").explain))
    expect(result.fetch("source")).to eq("[0]")
    expect(result.fetch("root").fetch("details")).to eq("index" => 0)
    expect(result.fetch("root").fetch("children").first.fetch("node").fetch("source_range")).to be_nil
    expect(JSON.parse(JSON.generate(JMESPath.compile("user.name").explain)))
      .to eq(JSON.parse(JSON.generate(field_chain)))
  end

  it "isolates repeated, configured, uncached, and concurrent inspections" do
    custom = JMESPath::Functions.default.with("custom", signature: []) { raise "executed" }
    variants = [JMESPath.compile("user.name"), JMESPath.compile("user.name", cache_expressions: false),
                JMESPath.compile("user.name", functions: custom, disable_visit_errors: true)]
    variants.each { |expression| 2.times { expect(expression.explain).to eq(field_chain) } }
    threads = Array.new(8) { Thread.new { Array.new(5) { variants.last.explain } } }
    expect(threads.flat_map(&:value)).to all(eq(field_chain))
  end

  it "inspects unknown, custom, and overridden functions without touching registries or callbacks" do
    events = []
    registry_class = Class.new(JMESPath::Functions) do
      %i[definition metadata names call call_with_context].each do |method|
        define_method(method) do |*args, **keywords, &block|
          events << method
          super(*args, **keywords, &block)
        end
      end
    end
    registry = registry_class.new.with("custom", signature: []) { events << :callback }
    registry = registry.with("length", signature: [[:any]]) { events << :callback }
    queries = %w[unknown(custom()) length(@)].map { |source| JMESPath.compile(source, functions: registry) }
    events.clear
    expect(queries.map { |query| query.explain.fetch(:root).fetch(:details) })
      .to eq([{ name: "unknown" }, { name: "length" }])
    expect(events).to be_empty
  end

  it "accepts no method arguments" do
    query = JMESPath.compile("@")
    expect { query.explain(nil) }.to raise_error(ArgumentError)
    expect { query.explain(format: :json) }.to raise_error(ArgumentError)
  end
end
