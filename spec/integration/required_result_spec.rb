# frozen_string_literal: true

require "tempfile"

RSpec.describe "Required query results" do
  it "returns selected values without copying or freezing them" do
    [false, 0, +"", +"Ada", [], {}].each do |value|
      expect(JMESPath.compile("user.name").fetch({ user: { name: value } })).to equal(value)
      expect(value).not_to be_frozen unless [false, 0].include?(value)
    end
  end

  it "rejects missing fields, explicit null, and out-of-range indexes" do
    [["user.name", {}], ["user.name", { user: { name: nil } }], ["items[3]", { items: [] }]].each do |source, data|
      expect { JMESPath.compile(source).fetch(data) }.to raise_error(JMESPath::Errors::NullResultError) { |error|
        expect(error.expression).to eq(source)
        expect(error.expression).to be_frozen
        expect(error.message).to eq("Expression returned null")
      }
    end
  end

  it "keeps nullable searches unchanged" do
    query = JMESPath.compile("user.name")
    expect(query.search({})).to be_nil
    expect(query.call({})).to be_nil
    expect { query.fetch({}) }.to raise_error(JMESPath::Errors::NullResultError)
  end

  it "accepts a non-null final result after an intermediate null" do
    expect(JMESPath.compile("value || `false`").fetch({})).to be(false)
  end

  it "rejects suppressed type and arity failures while honoring overrides" do
    failures = [["length(@)", JMESPath::Errors::InvalidTypeError], ["length()", JMESPath::Errors::InvalidArityError]]
    failures.each do |source, error|
      query = JMESPath.compile(source, disable_visit_errors: true)
      expect { query.fetch(7) }.to raise_error(JMESPath::Errors::NullResultError)
      expect { query.fetch(7, disable_visit_errors: false) }.to raise_error(error)
      expect { query.fetch(7) }.to raise_error(JMESPath::Errors::NullResultError)
    end
  end

  it "forwards positional options" do
    query = JMESPath.compile("length(@)")
    expect { query.fetch(7, { disable_visit_errors: true }) }.to raise_error(JMESPath::Errors::NullResultError)
    expect { query.fetch(7) }.to raise_error(JMESPath::Errors::InvalidTypeError)
  end

  it "overrides a saved registry without replacing saved suppression or later defaults" do
    functions = JMESPath::Functions.default.with("double", signature: [[:number]]) { |value| value * 2 }
    replacement = functions.with("double", signature: [[:number]], override: true) { |value| value * 3 }
    query = JMESPath.compile("double(price)", functions: functions, disable_visit_errors: true)
    expect(query.fetch({ price: 2 }, functions: replacement)).to eq(6)
    expect { query.fetch({}, functions: replacement) }.to raise_error(JMESPath::Errors::NullResultError)
    expect(query.fetch({ price: 2 })).to eq(4)
  end

  it "loads Ruby values and caller-owned streams from their current position" do
    query = JMESPath.compile("name")
    expect(query.fetch(Struct.new(:name).new("Ada"))).to eq("Ada")
    expect(JMESPath.compile("[0]").fetch([7])).to eq(7)
    io = StringIO.new('skip{"name":"Ada"}')
    io.pos = 4
    expect(query.fetch(io)).to eq("Ada")
    expect(io).not_to be_closed
  end

  it "loads files through Pathname and IO without closing caller-owned files" do
    Tempfile.create("jmespath-fetch") do |file|
      file.write('{"name":"Ada"}')
      file.flush
      expect(JMESPath.compile("name").fetch(Pathname.new(file.path))).to eq("Ada")
      file.rewind
      expect(JMESPath.compile("name").fetch(file)).to eq("Ada")
      expect(file).not_to be_closed
    end
  end

  it "preserves callback validation exceptions and backtraces under suppression" do
    failure = JMESPath::Errors::InvalidTypeError.new("callback defect")
    backtrace = ["application.rb:12:in 'callback'"]
    failure.set_backtrace(backtrace)
    functions = JMESPath::Functions.default.with("explode", signature: []) { raise failure }
    query = JMESPath.compile("explode()", functions: functions, disable_visit_errors: true)
    expect { query.fetch({}) }.to(raise_error do |error|
      expect(error).to equal(failure)
      expect(error.backtrace).to eq(backtrace)
    end)
  end

  it "rejects conflicting options before consuming input" do
    io = StringIO.new('{"name":"Ada"}')
    expect { JMESPath.compile("name").fetch(io, { disable_visit_errors: true }, disable_visit_errors: false) }
      .to raise_error(ArgumentError, /Conflicting option/)
    expect(io.pos).to eq(0)
  end

  it "invokes a side-effecting callback once for both false and null results" do
    [false, nil].each do |value|
      calls = 0
      functions = JMESPath::Functions.default.with("counted", signature: []) do
        calls += 1
        value
      end
      query = JMESPath.compile("counted()", functions: functions)
      if value.nil?
        expect { query.fetch({}) }.to raise_error(JMESPath::Errors::NullResultError)
      else
        expect(query.fetch({})).to be(false)
      end
      expect(calls).to eq(1)
    end
  end

  it "reports the compiled query independently of caller mutation" do
    source = +"user.name"
    query = JMESPath.compile(source)
    source.replace("changed")
    expect { query.fetch({}) }.to raise_error(JMESPath::Errors::NullResultError) { |error|
      expect(error.expression).to eq("user.name")
    }
  end

  it "propagates parse, function, option, and nesting failures" do
    expect { JMESPath.compile("@").fetch(StringIO.new("{")) }.to raise_error(JSON::ParserError)
    expect { JMESPath.compile("unknown()").fetch({}) }.to raise_error(JMESPath::Errors::UnknownFunctionError)
    expect { JMESPath.compile("[::0]").fetch([]) }.to raise_error(JMESPath::Errors::InvalidValueError)
    expect { JMESPath.compile("@").fetch({}, unexpected: true) }.to raise_error(ArgumentError)
    expect { JMESPath.compile("((@))").fetch({}, max_depth: 1) }.to raise_error(JMESPath::Errors::SyntaxError)
  end
end
