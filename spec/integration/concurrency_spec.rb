# frozen_string_literal: true

RSpec.describe "Concurrent searches" do
  it "shares compiled syntax without sharing evaluation state" do
    threads = 16.times.map do |id|
      Thread.new do
        100.times.map { |index| JMESPath.search("items[*].value", { items: [{ value: [id, index] }] }) }
      end
    end
    threads.each_with_index do |thread, id|
      expect(thread.value).to eq(100.times.map { |index| [[id, index]] })
    end
  end

  it "isolates validation failures in a shared function registry" do
    ready = Queue.new
    release = Queue.new
    functions = JMESPath::Functions.default.with("nested", signature: [[:number]]) do |number|
      ready << true
      release.pop
      JMESPath.search("length(@)", number)
    end
    workers = 4.times.map do |index|
      Thread.new do
        JMESPath.search("map(&nested(@), @)", [index], functions: functions, disable_visit_errors: true)
      rescue JMESPath::Errors::InvalidTypeError => e
        e
      end
    end
    4.times { ready.pop }
    expect(JMESPath.search("length(@)", 1, functions: functions, disable_visit_errors: true)).to be_nil
    4.times { release << true }
    errors = workers.map(&:value)
    expect(errors).to all(be_a(JMESPath::Errors::InvalidTypeError))
    expect(errors.map(&:object_id).uniq.length).to eq(4)
  ensure
    workers&.each do |worker|
      worker.kill if worker.alive?
      worker.join
    end
  end
end
