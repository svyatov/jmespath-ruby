# frozen_string_literal: true

RSpec.describe "Final review callbacks" do
  it "propagates nested callback validation failures through built-ins" do
    error = nil
    functions = JMESPath::Functions.default.with("nested", signature: []) do
      JMESPath.search("length(@)", 4)
    rescue JMESPath::Errors::InvalidTypeError => e
      error = e
      raise
    end
    ["nested()", "map(&nested(), @)", "min_by(@, &nested())"].each do |query|
      expect { JMESPath.search(query, [1], functions: functions, disable_visit_errors: true) }
        .to(raise_error { |caught| expect(caught).to equal(error) })
      expect(error.backtrace.first).to include("signature.rb")
    end
  end

  it "propagates nested callback arity failures and permits callbacks to rescue them" do
    functions = JMESPath::Functions.default.with("nested", signature: []) { JMESPath.search("length()", nil) }
    expect { JMESPath.search("map(&nested(), @)", [1], functions: functions, disable_visit_errors: true) }
      .to raise_error(JMESPath::Errors::InvalidArityError)
    recovered = functions.with("recovered", signature: []) do
      JMESPath.search("length()", nil)
    rescue JMESPath::Errors::InvalidArityError
      7
    end
    expect(JMESPath.search("map(&recovered(), @)", [1], functions: recovered, disable_visit_errors: true)).to eq([7])
  end

  it "propagates validation errors raised by application adapters" do
    adapter = Object.new
    adapter.define_singleton_method(:to_str) { JMESPath.search("length(@)", 4) }
    expect { JMESPath.search("length(@)", adapter, disable_visit_errors: true) }
      .to raise_error(JMESPath::Errors::InvalidTypeError)
  end

  it "still suppresses the current built-in validation failure" do
    expect(JMESPath.search("contains('abc', @)", 4, disable_visit_errors: true)).to be_nil
    expect(JMESPath.search("min_by(@, &key)", [{ key: false }], disable_visit_errors: true)).to be_nil
    expect(JMESPath.search("map(&length(@), @)", [4], disable_visit_errors: true)).to eq([nil])
  end
end
