# frozen_string_literal: true

require_relative "../support/wrappers"

RSpec.describe "Ruby data access" do
  it "prefers false string values but falls back from nil to symbols" do
    expect(JMESPath::DataAccess.field({ "x" => false, x: 7 }, "x")).to be(false)
    expect(JMESPath::DataAccess.field({ "x" => nil, x: 7 }, "x")).to eq(7)
  end

  it "preserves selected implicit-conversion objects" do
    array = Arrayish.new([1])
    expect(JMESPath::DataAccess.field(Hashish.new("x" => array), "x")).to equal(array)
  end

  it "restricts Struct lookup to members" do
    data = Struct.new(:x).new(3)
    expect(JMESPath::DataAccess.field(data, "x")).to eq(3)
    expect(JMESPath::DataAccess.field(data, "members")).to be_nil
    expect(JMESPath::DataAccess.field(nil, "x")).to be_nil
  end

  it "does not intern query identifiers" do
    key = "jmespath_unknown_#{Process.pid}_#{rand(1_000_000)}"
    JMESPath::DataAccess.field({}, key)
    expect(Symbol.all_symbols.map(&:name)).not_to include(key)
  end

  it "rejects malformed conversion returns" do
    expect { JMESPath::DataAccess.array(Arrayish.new("wrong")) }.to raise_error(TypeError)
  end
end
