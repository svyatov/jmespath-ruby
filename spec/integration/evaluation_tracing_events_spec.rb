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
end
