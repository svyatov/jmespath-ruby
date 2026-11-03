# frozen_string_literal: true

require "jmespath/cli"

RSpec.describe "Interactive function completion" do
  def complete(line, point = line.bytesize)
    JMESPath::CLI::InteractiveCompletion.new.complete(line, point: point)
  end

  it "inserts only a unique function name" do
    expect(complete("leng")).to eq(line: "length", point: 6, candidates: ["length"])
    expect(complete("length")).to eq(line: "length", point: 6, candidates: ["length"])
    expect(complete("items | leng(@)", 12)).to eq(line: "items | length(@)", point: 14, candidates: ["length"])
  end

  it "extends common prefixes and sorts ambiguous alternatives" do
    expect(complete("to")).to eq(line: "to_", point: 3, candidates: %w[to_array to_number to_string])
    expect(complete("to_")).to eq(line: "to_", point: 3, candidates: %w[to_array to_number to_string])
  end

  it "replaces the complete token while preserving surrounding Unicode" do
    line = "['é', lengzz(name), '✓']"
    expect(complete(line, 11)).to eq(line: "['é', length(name), '✓']", point: 13, candidates: ["length"])
    expect(complete("[lengzz]", 5)).to eq(line: "[length]", point: 7, candidates: ["length"])
  end

  ["", "zzzz", "123leng", "length(", "\"leng", "'leng", "`leng", "\"escaped\\\"leng",
   "'escaped\\'leng", "`escaped\\`leng", "'\\\\leng", "name\nleng", "\xFF".b].each do |line|
    it "preserves #{line.inspect} without candidates" do
      expect(complete(line)).to eq(line: line, point: line.bytesize, candidates: [])
    end
  end

  it "handles closed quotes and even backslash pairs" do
    expect(complete("'x' | leng")[:line]).to eq("'x' | length")
    expect(complete("\"\\\\\" | leng")[:line]).to eq("\"\\\\\" | length")
  end

  it "leaves empty prefixes and invalid cursor positions unchanged" do
    expect(complete("length", 0)).to eq(line: "length", point: 0, candidates: [])
    expect(complete("é leng", 1)).to eq(line: "é leng", point: 1, candidates: [])
    expect(complete("leng", -1)).to eq(line: "leng", point: -1, candidates: [])
    expect(complete("leng", 9)).to eq(line: "leng", point: 9, candidates: [])
  end

  it "completes inspection arguments but never command names" do
    expect(complete(":functions")[:candidates]).to eq([])
    expect(complete(" :explain leng")[:line]).to eq(" :explain length")
    expect(complete(":trace leng")[:line]).to eq(":trace length")
    expect(complete(":unknown leng")[:candidates]).to eq([])
    expect(complete(":explain", 3)[:candidates]).to eq([])
    expect(complete(":explain leng", 3)[:candidates]).to eq([])
  end

  it "uses registry names without evaluating queries" do
    registry = double("registry", names: %w[zeta zebra])
    expect(JMESPath).not_to receive(:compile)
    expect(JMESPath).not_to receive(:search)
    result = JMESPath::CLI::InteractiveCompletion.new(functions: registry).complete("ze", point: 2)
    expect(result).to eq(line: "ze", point: 2, candidates: %w[zebra zeta])
  end
end
