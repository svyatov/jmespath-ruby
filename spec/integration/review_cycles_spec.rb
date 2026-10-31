# frozen_string_literal: true

RSpec.describe "Final review regressions" do
  def deep_array(depth, cycle: false)
    root = []
    cursor = root
    depth.times do
      child = []
      cursor << child
      cursor = child
    end
    cursor << (cycle ? root : 1)
    root
  end

  it "rejects deeply nested cycles without exhausting the Ruby stack" do
    data = deep_array(10_000, cycle: true)
    expect { JMESPath.search("a == b", { a: data, b: data }) }.to raise_error(JMESPath::Errors::InvalidValueError)
    expect { JMESPath.search("to_string(@)", data) }.to raise_error(JMESPath::Errors::InvalidValueError)
  end

  it "compares deep acyclic values and reports serialization limits" do
    first = deep_array(10_000)
    second = deep_array(10_000)
    expect(JMESPath.search("a == b", { a: first, b: second })).to be(true)
    expect { JMESPath.search("to_string(@)", first) }.to raise_error(JMESPath::Errors::InvalidValueError)
  end
end
