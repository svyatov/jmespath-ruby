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
end
