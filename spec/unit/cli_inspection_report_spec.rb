# frozen_string_literal: true

require "jmespath/cli"

RSpec.describe "Interactive inspection reports" do
  def explain(source)
    JMESPath::CLI::InspectionReport.explain(JMESPath.compile(source).explain)
  end

  it "renders operation IDs, roles, details, and source locations in tree order" do
    expect(explain("user.name")).to eq(
      "#0 subexpression line 1, column 1 (bytes 0...9)\n  " \
      "step: #1 field line 1, column 1 (bytes 0...4) name=\"user\"\n  " \
      "step: #2 field line 1, column 6 (bytes 5...9) name=\"name\""
    )
  end

  it "uses character columns and counts source lines" do
    expect(explain("['é', length(@)]")).to include("line 1, column 7 (bytes 7...16)")
    expect(explain("[\n'é',\nlength(@)]")).to include("line 3, column 1")
  end

  it "labels unavailable source locations" do
    explanation = JMESPath.compile("@").explain
    explanation = explanation.merge(root: explanation[:root].merge(source_range: nil))
    expect(JMESPath::CLI::InspectionReport.explain(explanation)).to eq("#0 current location unavailable")
  end

  it "escapes control characters in nested literal details without losing Unicode" do
    text = explain('`{"x":["\u001b","é"]}`')
    expect(text).to include("value={", '"x"', '["\e", "é"]')
    expect(text).not_to include("\e")
    expect(explain("`1e999`")).to include("value=Infinity")
  end
end
