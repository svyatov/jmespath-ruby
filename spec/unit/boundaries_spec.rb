# frozen_string_literal: true

RSpec.describe "Validation boundaries" do
  it "rejects non-string expressions and non-hash options" do
    expect { JMESPath.compile(nil) }.to raise_error(ArgumentError)
    expect { JMESPath.search(nil, {}) }.to raise_error(ArgumentError, "Expression must be a String")
    expect { JMESPath.search("@", {}, nil) }.to raise_error(ArgumentError)
  end

  it "rejects malformed UTF-8 without transcoding it" do
    source = "\xFF".b.force_encoding(Encoding::UTF_8)
    expect { JMESPath.compile(source) }.to raise_error(JMESPath::Errors::SyntaxError)
  end

  it "rejects excessive syntax depth and invalid projection continuations" do
    expect { JMESPath.compile("a[0][0]", max_depth: 1) }.to raise_error(JMESPath::Errors::SyntaxError)
    expect { JMESPath.compile("a[*]()") }.to raise_error(JMESPath::Errors::SyntaxError)
    expect { JMESPath::Parser.new("@", max_depth: 0) }.to raise_error(ArgumentError)
  end

  it "maps serialization depth failures to invalid-value errors" do
    value = 101.times.reduce(nil) { |nested, _| [nested] }
    expect { JMESPath.search("to_string(@)", value) }.to raise_error(JMESPath::Errors::InvalidValueError)
  end

  it "returns null for numbers outside the finite floating-point range" do
    expect(JMESPath.search("to_number(@)", "1e9999")).to be_nil
    expect(JMESPath.search("type(@)", Object.new)).to be_nil
  end

  it "rejects invalid internal coercions instead of leaking Ruby method errors" do
    expect { JMESPath::Functions::Coercions.number(Float::INFINITY) }
      .to raise_error(JMESPath::Errors::InvalidTypeError)
    expect { JMESPath::Functions::Coercions.reference(nil) }
      .to raise_error(JMESPath::Errors::InvalidTypeError)
  end

  it "requires positive cache capacities" do
    expect { JMESPath::Cache.new(limit: 0) }.to raise_error(ArgumentError)
    expect { JMESPath::Cache.new(bytes: 0) }.to raise_error(ArgumentError)
  end

  it "owns mutable cache keys" do
    cache = JMESPath::Cache.new
    source = +"field"
    value = JMESPath.compile(source)
    cache.fetch(source, max_depth: 128) { value }
    source.replace("other")
    expect(cache.fetch("field", max_depth: 128) { raise "lost entry" }).to equal(value)
  end

  it "accepts concurrent duplicate misses without corrupting its byte budget" do
    cache = JMESPath::Cache.new(limit: 1, bytes: 1)
    ready = Queue.new
    release = Queue.new
    workers = 2.times.map do
      Thread.new do
        cache.fetch("a", max_depth: 128) do
          ready << true
          release.pop
          JMESPath.compile("a")
        end
      end
    end
    2.times { ready.pop }
    2.times { release << true }
    expect(workers.map(&:value).map { |expression| expression.search({ a: 2 }) }).to eq([2, 2])
    expect(cache.fetch("b", max_depth: 128) { JMESPath.compile("b") }.search({ b: 3 })).to eq(3)
  end
end
