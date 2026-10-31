# frozen_string_literal: true

require "stringio"
require "tempfile"
require "pathname"

RSpec.describe "Public search API" do
  it "searches Ruby values through the compatible entry point" do
    expect(JMESPath.search("foo.bar", { foo: { bar: "value" } })).to eq("value")
  end

  it "reads from an IO position without closing the caller's stream" do
    io = StringIO.new('skip{"foo":4}')
    io.pos = 4
    expect(JMESPath.search("foo", io)).to eq(4)
    expect(io).not_to be_closed
  end

  it "reads files through Pathname and IO" do
    Tempfile.create("jmespath") do |file|
      file.write('{"foo":4}')
      file.flush
      expect(JMESPath.search("foo", Pathname.new(file.path))).to eq(4)
      file.rewind
      expect(JMESPath.search("foo", file)).to eq(4)
      expect(file).not_to be_closed
    end
  end

  it "accepts positional and keyword options but rejects conflicting values" do
    expect(JMESPath.search("foo", { foo: 1 }, { cache_expressions: false }, cache_expressions: false)).to eq(1)
    expect { JMESPath.search("foo", {}, { cache_expressions: false }, cache_expressions: true) }
      .to raise_error(ArgumentError)
  end

  it "suppresses only library type and arity validation failures" do
    expect(JMESPath.search("length(a)", { a: 1 }, disable_visit_errors: true)).to be_nil
    expect { JMESPath.search("unknown()", {}, disable_visit_errors: true) }
      .to raise_error(JMESPath::Errors::UnknownFunctionError)
    error = JMESPath::Errors::InvalidTypeError.new("callback defect")
    registry = JMESPath::Functions.default.with("explode", signature: []) { raise error }
    expect { JMESPath.search("explode()", {}, functions: registry, disable_visit_errors: true) }
      .to(raise_error { |raised| expect(raised).to equal(error) })
  end
end
