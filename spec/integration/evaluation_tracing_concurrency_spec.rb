# frozen_string_literal: true

require "timeout"

RSpec.describe "Trace reference lifetime and concurrency" do
  it "keeps reference invocation counts inside synchronous projection context" do
    functions = JMESPath::Functions.default.with("twice", signature: [[:expref]]) do |reference|
      [reference.call({}), reference.call({})]
    end
    report = JMESPath.compile("items[*].twice(&missing)", functions: functions).trace({ items: [1, 2] })
    expect(report[:value]).to eq([[nil, nil], [nil, nil]])
    expect(report[:events].map { |event| event[:context] }).to eq([
                                                                    [{ operation_id: 0, index: 0 },
                                                                     { operation_id: 3, index: 0 }],
                                                                    [{ operation_id: 0, index: 0 },
                                                                     { operation_id: 3, index: 1 }],
                                                                    [{ operation_id: 0, index: 1 },
                                                                     { operation_id: 3, index: 2 }],
                                                                    [{ operation_id: 0, index: 1 },
                                                                     { operation_id: 3, index: 3 }]
                                                                  ])
  end

  it "does not evaluate unused expression references" do
    functions = JMESPath::Functions.default.with("ignore", signature: [[:expref]]) { |_reference| false }
    expect(JMESPath.compile("ignore(&missing)", functions: functions).trace({}))
      .to eq(value: false, events: [], truncated: false)
  end

  it "permits escaped references after successful and failed traces" do
    [false, true].each do |fail|
      saved = nil
      functions = JMESPath::Functions.default.with("save", signature: [[:expref]]) do |reference|
        saved = reference
        raise "callback" if fail

        7
      end
      query = JMESPath.compile("save(&missing)", functions: functions)
      if fail
        expect { query.trace({}) }.to raise_error("callback")
      else
        report = query.trace({})
        expect(report).to eq(value: 7, events: [], truncated: false)
      end
      expect(saved.call({})).to be_nil
      expect(saved.call({ missing: false })).to be(false)
      expect(report[:events]).to eq([]) unless fail
    end
  end

  it "isolates a trace started from another trace's callback" do
    nested = nil
    inside = false
    query = nil
    functions = JMESPath::Functions.default.with("again", signature: []) do
      if inside
        false
      else
        inside = true
        nested = query.trace({})
        7
      end
    end
    query = JMESPath.compile("{value: again(), missing: missing}", functions: functions)
    outer = query.trace({})
    expect(outer[:value]).to eq("value" => 7, "missing" => nil)
    expect(nested[:value]).to eq("value" => false, "missing" => nil)
    expect(outer[:events]).to eq(nested[:events])
    expect(outer[:events].length).to eq(1)
    expect(outer[:events]).not_to equal(nested[:events])
  end

  it "isolates eight top-level calls using the same expression" do
    query = JMESPath.compile("items[*].name")
    threads = 8.times.map do |index|
      Thread.new do
        items = Array.new(index) { { name: index } }
        items << {} if index.odd?
        query.trace({ items: items }, limit: 1)
      end
    end
    threads.map(&:value).each_with_index do |report, index|
      expect(report[:value]).to eq([index] * index)
      expect(report[:events].length).to eq(index.odd? ? 1 : 0)
      expect(report[:truncated]).to eq(index.odd?)
    end
  end

  it "keeps concurrent reference contexts separate without locking application callbacks" do
    ready = Queue.new
    proceed = Queue.new
    functions = JMESPath::Functions.default.with("mark", signature: [[:any]]) do |value|
      ready << true
      proceed.pop
      value
    end
    functions = functions.with("parallel", signature: [[:expref], [:array]]) do |reference, values|
      workers = values.map { |value| Thread.new { reference.call(value) } }
      begin
        Timeout.timeout(5) { 2.times { ready.pop } }
        2.times { proceed << true }
        workers.map(&:value)
      ensure
        workers.each { |worker| worker.kill if worker.alive? }
      end
    end
    query = JMESPath.compile("parallel(&mark(@).missing, @)", functions: functions)
    report = query.trace([{}, {}])
    expect(report[:value]).to eq([nil, nil])
    expect(report[:events].map { |event| event[:context] }.sort_by { |frames| frames.first[:index] })
      .to eq([[{ operation_id: 1, index: 0 }], [{ operation_id: 1, index: 1 }]])
    limited = query.trace([{}, {}], limit: 1)
    expect(limited[:events].length).to eq(1)
    expect(limited[:truncated]).to be(true)
    expect(limited[:value]).to eq([nil, nil])
  end
end
