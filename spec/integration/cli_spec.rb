# frozen_string_literal: true

require "open3"
require "rbconfig"
require "stringio"

RSpec.describe "Command-line queries" do
  def cli(arguments, input)
    require "jmespath/cli"
    output = StringIO.new
    errors = StringIO.new
    status = JMESPath::CLI.run(arguments, stdin: StringIO.new(input), stdout: output, stderr: errors)
    [status, output.string, errors.string]
  end

  it "prints one JSON result" do
    expect(cli(["foo.bar"], '{"foo":{"bar":2}}')).to eq([0, "2\n", ""])
    expect(cli(["missing"], "{}")).to eq([0, "null\n", ""])
  end

  it "reports malformed input and query failures on stderr" do
    status, output, error = cli(["@"], "not json")
    expect([status, output]).to eq([1, ""])
    expect(error).not_to be_empty
    expect(cli(["unknown()"], "{}").first).to eq(1)
    expect(cli(["a["], "{}").first).to eq(1)
  end

  it "reports a closed input stream" do
    require "jmespath/cli"
    input = StringIO.new
    input.close
    errors = StringIO.new
    status = JMESPath::CLI.run(["@"], stdin: input, stdout: StringIO.new, stderr: errors)
    expect(status).to eq(1)
    expect(errors.string).not_to be_empty
  end

  it "offers help and version without reading JSON" do
    expect(cli(["--help"], "invalid").first).to eq(0)
    expect(cli(["--version"], "invalid")[1]).to include(JMESPath::VERSION)
    expect(cli([], "{}").first).to eq(2)
    expect(cli(%w[a b], "{}").first).to eq(2)
  end

  it "explains validation in help and preserves failure output" do
    expect(cli(["--help"],
               "invalid")[1]).to include("Function arguments and expression-reference results are validated")
    expect(cli(["length(@)"], "4")).to eq([1, "", "Invalid argument 1 for length: number\n"])
    expect(cli([], "{}")).to eq([2, "", "Usage: jmespath EXPRESSION < document.json\n"])
  end

  %w[jmespath jmespath.rb].each do |name|
    it "runs the #{name} executable" do
      output, errors, status = Open3.capture3(
        RbConfig.ruby, File.expand_path("../../exe/#{name}", __dir__), "name",
        stdin_data: '{"name":"café"}'
      )
      expect(status).to be_success
      expect(output).to eq("\"café\"\n")
      expect(errors).to be_empty
    end
  end
end
