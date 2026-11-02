# frozen_string_literal: true

RSpec.describe "Null result errors" do
  it "owns immutable query text independently of caller mutation" do
    source = +"user.name"
    error = JMESPath::Errors::NullResultError.new(expression: source)
    expect(source).not_to be_frozen
    source.clear
    expect(error.expression).to eq("user.name")
    expect(error.expression).to be_frozen
    expect(error.message).to eq("Expression returned null")
    expect(error).to be_a(JMESPath::Errors::RuntimeError)
    expect(error).to be_a(JMESPath::Errors::Error)
  end
end

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

RSpec.describe JMESPath::Errors::UnknownFunctionError do
  it "preserves manual message construction and defaults" do
    error = described_class.new("manual")
    expect(error.message).to eq("manual")
    expect(error.function_name).to be_nil
    expect(error.suggestions).to eq([])
    expect(error.suggestions).to be_frozen
    expect(described_class.new.message).to eq("JMESPath::Errors::UnknownFunctionError")
    expect(error).to be_a(JMESPath::Errors::RuntimeError)
    expect(error).to be_a(JMESPath::Errors::Error)
  end

  it "owns immutable copies without freezing caller values" do
    name = +"lenght"
    candidate = +"length"
    suggestions = [candidate]
    error = described_class.new("Unknown function: lenght", function_name: name, suggestions: suggestions)
    name.clear
    candidate.clear
    suggestions.clear
    expect(error.function_name).to eq("lenght")
    expect(error.function_name).to be_frozen
    expect(error.suggestions).to eq(["length"])
    expect(error.suggestions).to be_frozen
    expect(error.suggestions.first).to be_frozen
    expect(error.message).to eq("Unknown function: lenght. Did you mean length?")
  end
end
