# frozen_string_literal: true

RSpec.describe "Trace collection" do
  let(:root) { JMESPath::Parser.new("items[?active].name").parse }
  let(:collector) { JMESPath::Tracing::Collector.new(root: root, limit: 1) }

  it "retains the first event and marks truncation only after another diagnostic" do
    collector.emit("filter_exclusion", root)
    report = collector.finish(nil)
    expect(report).to eq(value: nil, events: [
                           { type: "filter_exclusion", operation_id: 0, context: [], details: {} }
                         ], truncated: false)
    collector.emit("filter_exclusion", root)
    expect(report[:truncated]).to be(false)

    other = JMESPath::Tracing::Collector.new(root: root, limit: 1)
    3.times { other.emit("filter_exclusion", root) }
    expect(other.finish(false)).to eq(value: false, events: report[:events], truncated: true)
  end

  it "restores nested context even when evaluation raises" do
    collector.within(root, 3) do
      expect { collector.within(root, 4) { raise "failure" } }.to raise_error("failure")
      collector.emit("filter_exclusion", root)
    end
    frame = { operation_id: 0, index: 3 }
    expect(collector.finish(nil)[:events].first[:context]).to eq([frame])
  end

  it "numbers syntax in the public inspection order" do
    expect(collector.operation_id(root.children.fetch(0))).to eq(1)
    expect(collector.operation_id(root.children.fetch(2))).to eq(2)
    expect(collector.operation_id(root.children.fetch(1))).to eq(3)
    expect(JMESPath.compile("items[?active].name").explain[:root][:children].map { |entry| entry[:node][:id] })
      .to eq([1, 2, 3])
  end

  it "freezes diagnostics without freezing selected input" do
    name = +"x"
    collector.emit("field_null", root, name: name, reason: "missing")
    value = []
    report = collector.finish(value)
    event = report[:events].first
    expect(report).to be_frozen
    expect(report[:events]).to be_frozen
    expect(event).to be_frozen
    expect(event[:details]).to be_frozen
    expect(event[:details][:name]).to be_frozen
    expect(event[:context]).to be_frozen
    expect(name).not_to be_frozen
    expect(report[:value]).to equal(value)
    expect(value).not_to be_frozen
  end

  it "closes collection without stopping deferred evaluation" do
    collector.close
    result = collector.reference(root) { collector.within(root, 1) { 7 } }
    expect(result).to eq(7)
    expect(collector.finish(nil)).to eq(value: nil, events: [], truncated: false)
  end

  it "counts reference invocations independently for each operation" do
    2.times { collector.reference(root) { collector.emit("field_null", root) } }
    expect(collector.finish(nil)[:events].first[:context]).to eq([{ operation_id: 0, index: 0 }])
  end
end
