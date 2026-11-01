# frozen_string_literal: true

RSpec.describe "Function metadata" do
  let(:empty) { JMESPath::Functions.new }

  it "inspects an empty registry" do
    expect(empty.names).to eq([])
    expect(empty.names).to be_frozen
    expect(empty.metadata("missing")).to be_nil
  end

  it "reports declared unions, typed arrays, and variadic arguments without invoking callbacks" do
    registry = empty.with("sample", signature: [%i[string null], [:array_number]],
                                    variadic: true, description: "Read sample values.") { raise "Callback invoked" }
    metadata = registry.metadata("sample")
    expect(registry.names).to eq(["sample"])
    expect(metadata).to be_a(JMESPath::Functions::Metadata)
    expect(metadata.name).to eq("sample")
    expect(metadata.signature).to eq([%i[string null], [:array_number]])
    expect(metadata.variadic?).to be(true)
    expect(metadata.description).to eq("Read sample values.")
    expect(metadata).not_to respond_to(:implementation, :handler)
    expect(empty.names).to eq([])
  end

  it "reports fixed and zero-argument signatures and omitted descriptions" do
    registry = empty.with("strings", signature: [[:array_string]]) { nil }
                    .with("zero", signature: [], description: nil) { 0 }
    expect(registry.metadata("strings").signature).to eq([[:array_string]])
    expect(registry.metadata("strings").variadic?).to be(false)
    expect(registry.metadata("strings").description).to be_nil
    expect(registry.metadata("zero").signature).to eq([])
    expect(registry.metadata("zero").description).to be_nil
  end

  it "sorts names in case-sensitive lexical order" do
    registry = %w[z a A].reduce(empty) { |result, name| result.with(name, signature: []) { nil } }
    expect(registry.names).to eq(%w[A a z])
  end

  it "freezes the full returned snapshot" do
    registry = empty.with("sample", signature: [[:number]], description: "A sample.") { nil }
    names = registry.names
    metadata = registry.metadata("sample")
    expect(metadata).to be_frozen
    expect { names << "other" }.to raise_error(FrozenError)
    expect { names.first.replace("other") }.to raise_error(FrozenError)
    expect { metadata.name.replace("other") }.to raise_error(FrozenError)
    expect { metadata.signature << [:string] }.to raise_error(FrozenError)
    expect { metadata.signature.first << :null }.to raise_error(FrozenError)
    expect { metadata.description.replace("other") }.to raise_error(FrozenError)
  end

  it "copies mutable registration inputs without freezing caller-owned objects" do
    name = +"sample"
    description = +"Original."
    signature = [[:number]]
    registry = empty.with(name, signature: signature, description: description) { |value| value }
    metadata = registry.metadata("sample")
    name.replace("changed")
    description.replace("Changed.")
    signature.first << :string
    signature << [:null]
    expect(registry.names).to eq(["sample"])
    expect(registry.metadata("sample").description).to eq("Original.")
    expect(metadata.name).to eq("sample")
    expect(metadata.description).to eq("Original.")
    expect(metadata.signature).to eq([[:number]])
    expect { registry.call("sample", ["text"]) }.to raise_error(JMESPath::Errors::InvalidTypeError)
  end

  it "replaces all metadata on override while preserving earlier snapshots" do
    parent = empty.with("sample", signature: [[:number]], description: "Original.") { |value| value }
    snapshot = parent.metadata("sample")
    replacement = parent.with("sample", signature: [[:string]], override: true) { |value| value }
    described = parent.with("sample", signature: [], override: true, description: "Replacement.") { nil }
    expect(replacement.metadata("sample").description).to be_nil
    expect(replacement.metadata("sample").signature).to eq([[:string]])
    expect(described.metadata("sample").description).to eq("Replacement.")
    expect(parent.metadata("sample").description).to eq("Original.")
    expect(snapshot.signature).to eq([[:number]])
    expect(snapshot.description).to eq("Original.")
  end

  it "accepts empty descriptions and rejects other description types" do
    expect(empty.with("sample", signature: [], description: "") { nil }.metadata("sample").description).to eq("")
    [false, 42, :text].each do |description|
      expect { empty.with("sample", signature: [], description: description) { nil } }.to raise_error(ArgumentError)
    end
  end

  it "keeps shared inspection and independently derived registries isolated across threads" do
    shared = empty.with("shared", signature: [], description: "Shared.") { raise "Callback invoked" }
    snapshot = shared.metadata("shared")
    threads = 4.times.map do |index|
      Thread.new do
        name = "custom_#{index}"
        derived = shared.with(name, signature: []) { raise "Callback invoked" }
        10.times do
          expect(shared.names).to eq(["shared"])
          expect(shared.metadata(name)).to be_nil
          expect(derived.names).to eq([name, "shared"])
          expect(derived.metadata("shared").description).to eq("Shared.")
        end
      end
    end
    threads.each(&:value)
    expect(snapshot.description).to eq("Shared.")
  end
end
