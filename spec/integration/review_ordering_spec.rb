# frozen_string_literal: true

RSpec.describe "Final review ordering" do
  it "orders plain and wrapped strings with every comparison operator" do
    wrapper = Data.define(:text) { def to_str = text }
    { "<" => true, "<=" => true, ">" => false, ">=" => false }.each do |operator, expected|
      [[wrapper.new("a"), "b"], ["a", wrapper.new("b")], [wrapper.new("a"), wrapper.new("b")]].each do |left, right|
        expect(JMESPath.search("a #{operator} b", { a: left, b: right })).to be(expected)
      end
    end
  end
end
