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

  it "renders trace locations and item context through public operation IDs" do
    query = JMESPath.compile("items[*].name")
    report = query.trace({ "items" => [{}] })
    text = JMESPath::CLI::InspectionReport.trace(query.explain, report, limit: 1000)
    expect(text).to eq(
      "field_null #2 line 1, column 10 (bytes 9...13) name=\"name\" reason=\"missing\" context=[#0 index=0]\n" \
      "projection_omission #0 line 1, column 1 (bytes 0...13) context=[#0 index=0]"
    )
  end

  it "retains nested contexts and filter exclusions" do
    query = JMESPath.compile("groups[*].items[*].name")
    report = query.trace({ "groups" => [{ "items" => [{}] }] })
    text = JMESPath::CLI::InspectionReport.trace(query.explain, report, limit: 1000)
    expect(text).to include("context=[#0 index=0, #2 index=0]")
    query = JMESPath.compile("items[?active].name")
    report = query.trace({ "items" => [{ "active" => false }, { "active" => true, "name" => false }] })
    expect(JMESPath::CLI::InspectionReport.trace(query.explain, report, limit: 1000))
      .to include("filter_exclusion #0", "context=[#0 index=0]")
  end
end
