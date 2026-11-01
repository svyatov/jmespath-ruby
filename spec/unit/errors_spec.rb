# frozen_string_literal: true

RSpec.describe JMESPath::Errors::SyntaxError do
  it "distinguishes an omitted offset from explicit zero" do
    unknown = described_class.new("Bad query")
    known = described_class.new("Bad query", expression: "", position: 0)
    expect([unknown.location_known?, known.location_known?]).to eq([false, true])
    expect([unknown.position, known.position]).to eq([0, 0])
    expect([unknown.message, known.message]).to eq(["Bad query at byte 0"] * 2)
    expect([unknown.line, unknown.column]).to eq([1, 1])
  end

  it "owns the reason and expression independently of caller mutation" do
    reason = +"Bad query"
    source = +"'✓' $"
    error = described_class.new(reason, expression: source, position: 6)
    reason.replace("changed")
    source.clear
    expect(error.reason).to eq("Bad query")
    expect(error.reason).to be_frozen
    expect(error.expression).to eq("'✓' $")
    expect(error.expression).to be_frozen
    expect([error.position, error.line, error.column]).to eq([6, 1, 5])
    expect(error).to be_a(JMESPath::Errors::Error)
    expect(error).to be_a(StandardError)
  end

  it "preserves explicit negative offsets for callers" do
    error = described_class.new("Bad query", expression: "foo", position: -1)
    expect(error.position).to eq(-1)
    expect(error.message).to eq("Bad query at byte -1")
    expect(error.location_known?).to be(true)
  end
end
