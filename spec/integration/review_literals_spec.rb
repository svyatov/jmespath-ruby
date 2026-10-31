# frozen_string_literal: true

RSpec.describe "Final review literals" do
  it "rejects over-limit JSON literals consistently before and after compilation" do
    ["[[0]]", '{"a":{"b":0}}'].each do |literal|
      query = "#{96.chr}#{literal}#{96.chr}"
      expect { JMESPath.search(query, nil, max_depth: 1) }.to raise_error(JMESPath::Errors::SyntaxError)
      expect { JMESPath.compile(query).search(nil, max_depth: 1) }.to raise_error(JMESPath::Errors::SyntaxError)
      expect(JMESPath.search(query, nil, max_depth: 2)).to eq(JSON.parse(literal))
    end
    query = "#{96.chr}#{'[' * 129}0#{']' * 129}#{96.chr}"
    expect { JMESPath.compile(query) }.to raise_error(JMESPath::Errors::SyntaxError)
  end
end
