# frozen_string_literal: true

RSpec.describe "Configured compiled queries" do
  let(:functions) do
    JMESPath::Functions.default.with("double", signature: [[:number]]) { |value| value * 2 }
  end

  it "saves a custom registry for repeated searches and callable use" do
    query = JMESPath.compile("double(price)", functions: functions)
    expect(query.search({ price: 12 })).to eq(24)
    expect(query.call({ price: 15 })).to eq(30)
    expect(query).to be_frozen
  end

  it "saves suppression while retaining the custom registry for partial overrides" do
    query = JMESPath.compile("double(price)", functions: functions, disable_visit_errors: true)
    expect(query.search({ price: "invalid" })).to be_nil
    expect(query.search({ price: 12 }, max_depth: 128)).to eq(24)
    expect { query.search({ price: "invalid" }, disable_visit_errors: false) }
      .to raise_error(JMESPath::Errors::InvalidTypeError)
    expect(query.search({ price: "invalid" })).to be_nil
  end

  it "overrides one saved option without replacing the others or changing later searches" do
    replacement = functions.with("double", signature: [[:number]], override: true) { |value| value * 3 }
    query = JMESPath.compile("double(price)", functions: functions, disable_visit_errors: true)
    expect(query.search({ price: 2 }, functions: replacement)).to eq(6)
    expect(query.search({ price: nil }, functions: replacement)).to be_nil
    expect(query.search({ price: 2 })).to eq(4)
    expect { query.search({}, { disable_visit_errors: true }, disable_visit_errors: false) }
      .to raise_error(ArgumentError, /Conflicting option/)
  end

  it "keeps configured registries out of the shared syntax cache" do
    configured = JMESPath.compile("double(price)", functions: functions)
    plain = JMESPath.compile("double(price)")
    expect { plain.search({ price: 2 }) }.to raise_error(JMESPath::Errors::UnknownFunctionError)
    expect(configured.search({ price: 2 })).to eq(4)
    expect(JMESPath.compile("length(@)").call("abc")).to eq(3)
  end

  it "validates saved options before evaluating a document" do
    expect { JMESPath.compile("@", functions: nil) }.to raise_error(ArgumentError, /registry/)
    expect { JMESPath.compile("@", disable_visit_errors: nil) }.to raise_error(ArgumentError, /boolean/)
  end

  it "applies saved suppression to native string functions and their non-string inputs" do
    query = JMESPath.compile("length(@)", disable_visit_errors: true)
    expect(query.call("abc")).to eq(3)
    expect(query.call([1, 2])).to eq(2)
    expect(query.call(5)).to be_nil
    expect { query.call(5, disable_visit_errors: false) }.to raise_error(JMESPath::Errors::InvalidTypeError)
  end

  it "honors built-in overrides inside compiled expression references" do
    replacement = functions.with("length", signature: [[:string]], override: true) { |value| value.length * 2 }
    query = JMESPath.compile("map(&length(@), @)", functions: replacement)
    expect(query.search(%w[a abc])).to eq([2, 6])
  end

  it "keeps unchanged string functions while applying other built-in overrides" do
    replacement = functions.with("reverse", signature: [[:string]], override: true) { "custom" }
    query = JMESPath.compile("[length(@), reverse(@)]", functions: replacement)
    expect(query.call("abc")).to eq([3, "custom"])
  end

  it "retains custom dispatch in a registry subclass" do
    registry_class = Class.new(JMESPath::Functions) do
      def call(*)
        42
      end
    end
    query = JMESPath.compile("length(@)", functions: registry_class.new)
    expect(query.call("abc")).to eq(42)
  end

  it "delays unknown function failure until its arguments have been evaluated" do
    reads = []
    query = JMESPath.compile("absent(value)", functions: functions)
    data = Hash.new { |_, key| reads << key }
    expect { query.search(data) }.to raise_error(JMESPath::Errors::UnknownFunctionError)
    expect(reads).to eq(["value"])
  end

  it "preserves nested callback validation failures under saved suppression" do
    failure = nil
    nested = functions.with("nested", signature: []) do
      JMESPath.search("length(@)", 4)
    rescue JMESPath::Errors::InvalidTypeError => e
      failure = e
      raise
    end
    query = JMESPath.compile("map(&nested(), @)", functions: nested, disable_visit_errors: true)
    expect { query.search([1]) }.to(raise_error { |error| expect(error).to equal(failure) })
    expect(query.search([])).to eq([])
  end

  it "propagates adapter errors and still loads stream inputs" do
    failure = TypeError.new("adapter failure")
    adapter = Object.new
    adapter.define_singleton_method(:to_hash) { raise failure }
    query = JMESPath.compile("double(price)", functions: functions, disable_visit_errors: true)
    expect { query.search(adapter) }.to(raise_error { |error| expect(error).to equal(failure) })
    expect(query.call(StringIO.new('{"price":9}'))).to eq(18)
  end

  it "retains nesting limits and configured fallback operations" do
    query = JMESPath.compile("{result: double(price)}", functions: functions, max_depth: 5)
    expect(query.search({ price: 3 })).to eq("result" => 6)
    expect { query.search({ price: 3 }, max_depth: 1) }.to raise_error(JMESPath::Errors::SyntaxError)
    expect(query.search({ price: 3 })).to eq("result" => 6)
  end

  it "shares saved options across concurrent searches with independent overrides" do
    query = JMESPath.compile("double(price)", functions: functions, disable_visit_errors: true)
    workers = 8.times.map do |index|
      Thread.new do
        [query.call({ price: index }), query.call({ price: nil }, disable_visit_errors: true)]
      end
    end
    expect(workers.map(&:value)).to eq(8.times.map { |index| [index * 2, nil] })
  end
end
