# frozen_string_literal: true

require "tempfile"

RSpec.describe "Non-raising search input" do
  it "captures malformed JSON without closing caller streams" do
    input = StringIO.new("invalid")
    result = JMESPath.compile("@").try_search(input)
    expect(result.success?).to be(false)
    expect(result.error).to be_a(JSON::ParserError)
    expect(input).not_to be_closed
  end

  it "captures malformed file JSON and preserves caller ownership" do
    Tempfile.create("try-search") do |file|
      file.write("invalid")
      file.rewind
      expression = JMESPath.compile("@")
      expect(expression.try_search(file).error).to be_a(JSON::ParserError)
      expect(file).not_to be_closed
      expect(expression.try_search(Pathname.new(file.path)).error).to be_a(JSON::ParserError)
    end
  end

  it "captures missing paths" do
    result = JMESPath.compile("@").try_search(Pathname.new("/nonexistent-jmespath-try-search/document.json"))
    expect(result.success?).to be(false)
    expect(result.error).to be_a(Errno::ENOENT)
  end

  it "retains the original native exception and backtrace" do
    input = StringIO.new("{}")
    input.close
    observed = nil
    backtrace = nil
    tracer = TracePoint.new(:raise) do |event|
      if event.raised_exception.is_a?(IOError) && observed.nil?
        observed = event.raised_exception
        backtrace = observed.backtrace.dup
      end
    end
    result = tracer.enable { JMESPath.compile("@").try_search(input) }
    expect(result.error).to equal(observed)
    expect(result.error.backtrace).to eq(backtrace)
  ensure
    tracer&.disable
  end

  it "captures a closed native file stream" do
    Tempfile.create("try-search") do |file|
      file.close
      expect(JMESPath.compile("@").try_search(file).error).to be_a(IOError)
    end
  end

  it "reads from the current position and preserves caller streams after evaluation failure" do
    input = StringIO.new("skip4")
    input.pos = 4
    result = JMESPath.compile("length(@)").try_search(input)
    expect(result.error).to be_a(JMESPath::Errors::InvalidTypeError)
    expect(input).not_to be_closed
    expect(input.pos).to eq(5)
    input = StringIO.new("skip[1]")
    input.pos = 4
    expect(JMESPath.compile("length(@)").try_search(input).value).to eq(1)
    expect(input).not_to be_closed
  end

  it "closes owned files after success, parsing failure, and read failure" do
    opened = []
    allow(File).to receive(:open).and_wrap_original do |original, *args, **keywords, &block|
      next original.call(*args, **keywords) unless block

      original.call(*args, **keywords) do |file|
        opened << file
        block.call(file)
      end
    end
    Tempfile.create("try-search") do |file|
      file.write("[]")
      file.flush
      expect(JMESPath.compile("@").try_search(Pathname.new(file.path)).value).to eq([])
      file.rewind
      file.write("xx")
      file.flush
      expect(JMESPath.compile("@").try_search(Pathname.new(file.path)).error).to be_a(JSON::ParserError)
    end
    expect(JMESPath.compile("@").try_search(Pathname.new(Dir.tmpdir)).error).to be_a(Errno::EISDIR)
    expect(opened.length).to eq(3)
    expect(opened).to all(be_closed)
  end

  [IOError, Errno::EIO, JSON::ParserError, JSON::NestingError, JMESPath::Errors::InvalidValueError].each do |klass|
    it "propagates #{klass} from an overridden read exactly once" do
      error = klass.new("application input")
      error.set_backtrace(["input.rb:1"])
      calls = 0
      input = StringIO.new("{}")
      input.define_singleton_method(:read) do
        calls += 1
        raise error
      end
      expect { JMESPath.compile("@").try_search(input) }.to(raise_error do |caught|
        expect(caught).to equal(error)
        expect(caught.backtrace).to eq(["input.rb:1"])
      end)
      expect(calls).to eq(1)
      expect(input).not_to be_closed
    end
  end

  %i[to_path to_s].each do |conversion|
    it "propagates a nested query failure from #{conversion}" do
      observed = nil
      value = Object.new
      value.define_singleton_method(conversion) do
        JMESPath.search("length(@)", 4)
      rescue JMESPath::Errors::InvalidTypeError => e
        observed = e
        raise
      end
      input = if conversion == :to_path
                Pathname.new("unused").tap do |path|
                  path.define_singleton_method(:to_path) { value.to_path }
                end
              else
                StringIO.new.tap { |stream| stream.define_singleton_method(:read) { value } }
              end
      expect { JMESPath.compile("@").try_search(input) }
        .to(raise_error { |caught| expect(caught).to equal(observed) })
    end
  end

  it "preserves ordinary string inputs" do
    expect(JMESPath.compile("@").try_search("{invalid").value).to eq("{invalid")
  end
end
