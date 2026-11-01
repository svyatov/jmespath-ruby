# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

RSpec.describe "Documentation checks" do
  def check_docs(method_docs: "# @return [Integer] the answer", readme: "# Demo\n")
    Dir.mktmpdir("jmespath-docs") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      source = "# A documented example module.\nmodule Demo\n  # The answer.\n  #{method_docs}\n"
      source += "  def self.answer\n    42\n  end\nend\n"
      File.write(File.join(root, "lib/demo.rb"), source)
      File.write(File.join(root, "README.md"), readme)
      Open3.capture3(RbConfig.ruby, File.expand_path("../../script/check_docs.rb", __dir__), "--root", root)
    end
  end

  it "accepts documented methods" do
    output, error, status = check_docs
    expect(status).to be_success, "#{output}\n#{error}"
  end

  it "accepts the core Range type used by source locations" do
    output, error, status = check_docs(method_docs: "# @return [Range<Integer>, nil] source range")
    expect(status).to be_success, "#{output}\n#{error}"
  end

  it "rejects absent return documentation" do
    output, = check_docs(method_docs: "")
    expect(output).to include("return")
  end

  it "rejects unresolved type references" do
    output, = check_docs(method_docs: "# @return [MissingType] absent")
    expect(output).to include("MissingType")
  end

  it "rejects missing local links" do
    output, = check_docs(readme: "[Missing](missing.md)\n")
    expect(output).to include("Missing local link")
  end

  it "executes documented examples and rejects incorrect results" do
    fence = 96.chr * 3
    output, = check_docs(readme: "# Demo\n#{fence}ruby\nDemo.answer #=> 99\n#{fence}\n")
    expect(output).to include("Example mismatch")
  end
end
