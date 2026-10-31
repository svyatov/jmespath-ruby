# frozen_string_literal: true

require "open3"
require "rbconfig"

RSpec.describe "Final review indices" do
  it "returns null for indices larger than native machine integers" do
    ["9" * 100, "-#{'9' * 100}"].each do |index|
      expect(JMESPath.search("[#{index}]", [1])).to be_nil
      expect(JMESPath.search("[#{index}]", [])).to be_nil
      expect(JMESPath.search("[#{index}]", nil)).to be_nil
    end
  end
end

RSpec.describe "Large-index command line queries" do
  it "prints null through both executables without a Ruby traceback" do
    %w[jmespath jmespath.rb].each do |name|
      path = File.expand_path("../../exe/#{name}", __dir__)
      output, error, status = Open3.capture3(RbConfig.ruby, path, "[#{'9' * 100}]", stdin_data: "[1]")
      expect([output, error, status.exitstatus]).to eq(["null\n", "", 0])
    end
  end
end
