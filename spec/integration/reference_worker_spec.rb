# frozen_string_literal: true

require "rbconfig"

RSpec.describe "Differential reference process" do
  it "exchanges JSON with an isolated Ruby process" do
    require_relative "../../script/support/reference_worker"
    script = <<~RUBY
      $stdout.sync = true
      require "json"
      STDIN.each_line { |line| puts JSON.generate(JSON.parse(line).merge("seen" => true)) }
    RUBY
    worker = ReferenceWorker.new([RbConfig.ruby, "-e", script])
    expect(worker.request({ "value" => [1, false, nil] })).to eq("value" => [1, false, nil], "seen" => true)
  ensure
    worker&.close
  end
end
