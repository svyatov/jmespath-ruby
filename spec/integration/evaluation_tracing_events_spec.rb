# frozen_string_literal: true

RSpec.describe "Trace diagnostics" do
  [
    [{}, "missing"],
    [{ x: nil }, "null"],
    [{ "x" => nil }, "null"],
    [nil, "non_object"],
    [4, "non_object"]
  ].each do |input, reason|
    it "classifies #{input.inspect} as #{reason}" do
      expect(JMESPath.compile("x").trace(input)[:events].first[:details]).to eq(name: "x", reason: reason)
    end
  end

  it "preserves symbol fallback and non-nil defaults without diagnostics" do
    [{ "x" => nil, x: false }, Hash.new(false)].each do |input|
      expect(JMESPath.compile("x").trace(input)).to eq(value: false, events: [], truncated: false)
    end
  end

  it "does not freeze caller strings or retain input values in diagnostics" do
    data = { x: nil, other: +"secret" }
    report = JMESPath.compile("x").trace(data)
    expect(report).to be_frozen
    event = report[:events].first
    expect(event).to be_frozen
    expect(event[:details][:name]).to be_frozen
    expect(event[:type]).to be_frozen
    expect(JSON.generate(event)).not_to include("secret")
    expect(data).not_to be_frozen
    expect(data[:other]).not_to be_frozen
  end

  it "recognizes absence among unrelated string, symbol, and numeric keys" do
    data = { y: 1, "other" => 2, 3 => 4 }
    expect(JMESPath.compile("x").trace(data)[:events].first[:details][:reason]).to eq("missing")
  end

  it "explains omissions while retaining false projected values" do
    query = JMESPath.compile("items[*].name")
    report = query.trace({ items: [{ name: "Ada" }, {}, { name: false }] })
    expect(report[:value]).to eq(["Ada", false])
    expected = [
      { type: "field_null", operation_id: 2, context: [{ operation_id: 0, index: 1 }],
        details: { name: "name", reason: "missing" } },
      { type: "projection_omission", operation_id: 0,
        context: [{ operation_id: 0, index: 1 }], details: {} }
    ]
    expect(report[:events]).to eq(expected)
  end

  it "keeps outer frames and original filter indexes" do
    data = { groups: [{ items: [{ active: false }, { active: true }] }] }
    report = JMESPath.compile("groups[*].items[?active].name").trace(data)
    expect(report[:value]).to eq([[]])
    expected = [
      { type: "filter_exclusion", operation_id: 2,
        context: [{ operation_id: 0, index: 0 }, { operation_id: 2, index: 0 }], details: {} },
      { type: "field_null", operation_id: 5,
        context: [{ operation_id: 0, index: 0 }, { operation_id: 2, index: 1 }],
        details: { name: "name", reason: "missing" } },
      { type: "projection_omission", operation_id: 2,
        context: [{ operation_id: 0, index: 0 }, { operation_id: 2, index: 1 }], details: {} }
    ]
    expect(report[:events]).to eq(expected)
  end

  it "records null filter conditions before exclusions" do
    report = JMESPath.compile("items[?active].name").trace({ items: [{}, { active: true, name: false }] })
    expect(report[:value]).to eq([false])
    expected = [
      ["field_null",
       [{ operation_id: 0, index: 0 }]],
      ["filter_exclusion",
       [{ operation_id: 0, index: 0 }]]
    ]
    expect(report[:events].map { |event| [event[:type], event[:context]] }).to eq(expected)
  end

  it "uses ordinal object positions without extra key enumeration" do
    values = { first: {}, second: { name: false } }
    values.define_singleton_method(:each_key) { raise "extra enumeration" }
    report = JMESPath.compile("items.*.name").trace({ items: values })
    expect(report[:value]).to eq([false])
    expect(report[:events].map { |event| event[:context] })
      .to eq([[{ operation_id: 0, index: 0 }], [{ operation_id: 0, index: 0 }]])
  end

  it "indexes the local sequence after slices, flattening, and pipes" do
    [
      ["items[1:].name", { items: [{ name: 1 }, {}] }, 0],
      ["items[].name", { items: [[{}], [{ name: false }]] }, 0],
      ["items | [*].name", { items: [{}, { name: false }] }, 2]
    ].each do |source, data, id|
      report = JMESPath.compile(source).trace(data)
      expect(report[:events].first[:context]).to eq([{ operation_id: id, index: 0 }])
      expect(report[:value]).to eq(JMESPath.search(source, data))
    end
  end

  it "does not report omissions for nil inputs or empty collections" do
    ["items[*].name", "items.*.name", "items[?active].name"].each do |source|
      query = JMESPath.compile(source)
      expect(query.trace({ items: nil })[:events].map { |event| event[:type] }).to eq(["field_null"])
      expect(query.trace({ items: [] })[:events]).to eq([])
      expect(query.trace({ items: {} })[:events]).to eq([])
    end
  end
end
