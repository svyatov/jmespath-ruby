# frozen_string_literal: true

require "open3"
require "rbconfig"
require "stringio"
require "timeout"

RSpec.describe "Command-line queries" do
  def usage
    "Usage: jmespath [--pretty] [--file PATH] (EXPRESSION | --query-file PATH)\n       " \
      "jmespath --validate (EXPRESSION | --query-file PATH)\n"
  end

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

  it "reports registered-name suggestions without changing failure status" do
    expect(cli(["lenght(name)"], '{"name":"Ada"}'))
      .to eq([1, "", "Unknown function: lenght. Did you mean length?\n"])
    expect(cli(["zzzzzzzz()"], "{}"))
      .to eq([1, "", "Unknown function: zzzzzzzz\n"])
    expect(cli(["--help"], "invalid")[1]).to include("Unknown functions suggest similar registered names")
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
    expected = "Invalid argument 1 for length: expected string, array, or object; received number " \
               "at line 1, column 1\nlength(@)\n^\n"
    expect(cli(["length(@)"], "4")).to eq([1, "", expected])
    expect(cli([], "{}")).to eq([2, "", usage])
  end

  {
    "items[" => ["{}", "Expected an array index at line 1, column 7\nitems[\n      ^\n"],
    "length()" => ["{}", "Invalid number of arguments for length: expected 1; received 0 " \
                         "at line 1, column 1\nlength()\n^\n"],
    "merge()" => ["{}", "Invalid number of arguments for merge: expected at least 1; received 0 " \
                        "at line 1, column 1\nmerge()\n^\n"],
    "join(',', @)" => ["[1]", "Invalid argument 2 for join: expected array of strings; received array " \
                              "at line 1, column 1\njoin(',', @)\n^\n"],
    "sum(@)" => ['["x"]', "Invalid argument 1 for sum: expected array of numbers; received array " \
                          "at line 1, column 1\nsum(@)\n^\n"],
    "sort_by(@, &key)" => ['[{"key":true}]',
                           "Invalid expression result for argument 2 of sort_by: expected number or string; " \
                           "received boolean at line 1, column 1\nsort_by(@, &key)\n^\n"],
    "length(reverse(@))" => ["4", "Invalid argument 1 for reverse: expected string or array; received number " \
                                  "at line 1, column 8\nlength(reverse(@))\n       ^\n"],
    "['✓', length(@)]" => ["4", "Invalid argument 1 for length: expected string, array, or object; received number " \
                                "at line 1, column 7\n['✓', length(@)]\n      ^\n"],
    "[\n\tlength(@)]" => ["4", "Invalid argument 1 for length: expected string, array, or object; received number " \
                               "at line 2, column 2\n    length(@)]\n    ^\n"],
    "['\e', length(@)]" => ["4", "Invalid argument 1 for length: expected string, array, or object; received number " \
                                 "at line 1, column 7\n['\\e', length(@)]\n       ^\n"],
    "[::0]" => ["[]", "Slice step cannot be zero\n"]
  }.each do |query, (input, expected)|
    it "renders the failure for #{query.inspect}" do
      expect(cli([query], input)).to eq([1, "", expected])
    end
  end

  def injected_failure(error, query = "length(@)")
    allow(JMESPath).to receive(:search).with(query, {}).and_raise(error)
    cli([query], "{}")
  end

  it "escapes manually constructed failures without inventing metadata" do
    [JMESPath::Errors::InvalidTypeError, JMESPath::Errors::InvalidArityError].each do |type|
      expect(injected_failure(type.new("Manual\nerror\e"))).to eq([1, "", "Manual\\nerror\\e\n"])
    end
  end

  {
    function_name: nil, argument_position: nil, expected_types: nil, actual_type: nil,
    validation_stage: nil, empty_types: [], invalid_position: 0, invalid_stage: :other
  }.each do |field, value|
    it "retains source context with incomplete type metadata: #{field}" do
      metadata = { function_name: "length", argument_position: 1, expected_types: [:string],
                   actual_type: :number, validation_stage: :argument, source_range: 0...9 }
      key = { empty_types: :expected_types, invalid_position: :argument_position,
              invalid_stage: :validation_stage }.fetch(field, field)
      error = JMESPath::Errors::InvalidTypeError.new("Manual", **metadata, key => value)
      original = [error.message, error.source_range, error.expected_types]
      2.times do
        expect(injected_failure(error)).to eq([1, "", "Manual at line 1, column 1\nlength(@)\n^\n"])
        expect([error.message, error.source_range, error.expected_types]).to eq(original)
      end
    end
  end

  it "renders complete validation details without source metadata" do
    error = JMESPath::Errors::InvalidTypeError.new(
      "Manual", function_name: "custom", argument_position: 1, expected_types: [:expref],
                actual_type: :unknown, validation_stage: :argument
    )
    expect(injected_failure(error))
      .to eq([1, "", "Invalid argument 1 for custom: expected expref; received unknown\n"])
  end

  {
    function_name: nil, expected_arity: nil, actual_arity: nil, variadic: nil,
    negative_expected: -1, negative_actual: -1
  }.each do |field, value|
    it "falls back for incomplete arity metadata: #{field}" do
      metadata = { function_name: "custom", expected_arity: 0, actual_arity: 1, variadic: false }
      key = { negative_expected: :expected_arity, negative_actual: :actual_arity }.fetch(field, field)
      error = JMESPath::Errors::InvalidArityError.new("Manual", **metadata, key => value)
      expect(injected_failure(error)).to eq([1, "", "Manual\n"])
    end
  end

  it "retains a zero expected arity" do
    error = JMESPath::Errors::InvalidArityError.new(
      "Manual", function_name: "custom", expected_arity: 0, actual_arity: 1, variadic: false
    )
    expect(injected_failure(error))
      .to eq([1, "", "Invalid number of arguments for custom: expected 0; received 1\n"])
  end

  [nil, -1...4, 8...7, 8...8, 8..17, 8...30, 3...17, 0...3, (..9), (0...)].each do |range|
    it "omits unusable runtime source range #{range.inspect}" do
      error = JMESPath::Errors::InvalidTypeError.new("Manual", source_range: range)
      expect(injected_failure(error, "['✓', length(@)]")).to eq([1, "", "Manual\n"])
    end
  end

  it "omits an invalid source encoding" do
    error = JMESPath::Errors::InvalidTypeError.new("Manual", source_range: 0...1)
    expect(injected_failure(error, "\xFF".b.force_encoding(Encoding::UTF_8))).to eq([1, "", "Manual\n"])
  end

  it "omits source context when no query is available" do
    require "jmespath/cli"
    error = JMESPath::Errors::InvalidTypeError.new("Manual", source_range: 0...1)
    expect(JMESPath::CLI::FailureDiagnostic.format(error, nil)).to eq("Manual")
  end

  it "excludes document fragments from malformed JSON diagnostics" do
    expect(cli(["@"], '{"private_marker":BROKEN}')).to eq([1, "", "Invalid JSON input\n"])
    expect(cli(["items["], '{"private_marker":BROKEN}')).to eq([1, "", "Invalid JSON input\n"])
  end

  it "explains located query failures in help" do
    expect(cli(["--help"], "invalid")[1]).to include("Query failures include source locations when available.")
  end

  [["--help"], ["-h"], ["--version"], [], %w[a b]].each do |arguments|
    it "does not read stdin for #{arguments.inspect}" do
      require "jmespath/cli"
      input = double("unreadable input")
      output = StringIO.new
      errors = StringIO.new
      status = JMESPath::CLI.run(arguments, stdin: input, stdout: output, stderr: errors)
      if arguments.length == 1
        expect(status).to eq(0)
        expect(output.string).not_to be_empty
        expect(errors.string).to be_empty
      else
        expect([status, output.string, errors.string])
          .to eq([2, "", usage])
      end
    end
  end

  [IOError.new("Read\nfailed\e"), Errno::EIO.new("Read\nfailed\e")].each do |error|
    it "escapes #{error.class} input failures" do
      require "jmespath/cli"
      input = double("failed input")
      allow(input).to receive(:read).and_raise(error)
      output = StringIO.new
      errors = StringIO.new
      status = JMESPath::CLI.run(["@"], stdin: input, stdout: output, stderr: errors)
      prefix = error.is_a?(IOError) ? "" : "Input/output error - "
      expect([status, output.string, errors.string]).to eq([1, "", "#{prefix}Read\\nfailed\\e\n"])
    end
  end

  [ArgumentError, RuntimeError].each do |type|
    it "propagates unrelated #{type} failures" do
      error = type.new("Application failure")
      allow(JMESPath).to receive(:search).with("@", {}).and_raise(error)
      expect { cli(["@"], "{}") }.to(raise_error { |failure| expect(failure).to equal(error) })
    end
  end

  {
    ["--validate", "unknown()"] => [0, ""],
    ["--validate", "length()"] => [0, ""],
    ["--validate", "items[*].name"] => [0, ""],
    ["--validate", "items[?active"] => [1, "Expected rbracket, received eof at line 1, column 14\n" \
                                           "items[?active\n             ^\n"],
    ["--validate", ""] => [1, "Expected an expression at line 1, column 1\n\n^\n"],
    ["--validate", "--help"] => [1, "Expected a digit at line 1, column 1\n--help\n^\n"],
    ["--validate", "--version"] => [1, "Expected a digit at line 1, column 1\n--version\n^\n"],
    ["--validate", "[::0]"] => [1, "Slice step cannot be zero\n"]
  }.each do |arguments, (expected_status, expected_errors)|
    it "validates #{arguments.last.inspect} without reading stdin" do
      require "jmespath/cli"
      output = StringIO.new
      errors = StringIO.new
      status = JMESPath::CLI.run(arguments, stdin: double("unreadable stdin"), stdout: output, stderr: errors)
      expect([status, output.string, errors.string]).to eq([expected_status, "", expected_errors])
    end
  end

  [["--validate"], ["--validate", "@", "extra"]].each do |arguments|
    it "rejects invalid validation usage #{arguments.inspect} without reading stdin" do
      require "jmespath/cli"
      output = StringIO.new
      errors = StringIO.new
      status = JMESPath::CLI.run(arguments, stdin: double("unreadable stdin"), stdout: output, stderr: errors)
      expect([status, output.string, errors.string]).to eq([2, "", usage])
    end
  end

  it "documents syntax-only validation, stdin independence, and statuses" do
    help = cli(["--help"], "invalid")[1]
    expect(help).to include("--validate EXPRESSION", "without reading stdin", "syntax only",
                            "0 for valid syntax", "1 for query failures", "2 for usage failures")
  end

  it "propagates unrelated exceptions during validation" do
    failure = RuntimeError.new("Validation defect")
    allow(JMESPath).to receive(:validate).with("@").and_raise(failure)
    expect { cli(["--validate", "@"], "invalid") }.to(raise_error { |error| expect(error).to equal(failure) })
  end

  %w[jmespath jmespath.rb].each do |name|
    {
      ["items["] => ["{}", 1, "Expected an array index at line 1, column 7\nitems[\n      ^\n"],
      ["length(@)"] => ["4", 1,
                        "Invalid argument 1 for length: expected string, array, or object; received number " \
                        "at line 1, column 1\nlength(@)\n^\n"],
      ["length()"] => ["{}", 1, "Invalid number of arguments for length: expected 1; received 0 " \
                                "at line 1, column 1\nlength()\n^\n"],
      ["lenght(name)"] => ["{}", 1, "Unknown function: lenght. Did you mean length?\n"],
      ["[::0]"] => ["[]", 1, "Slice step cannot be zero\n"],
      ["@"] => ['{"private_marker":BROKEN}', 1, "Invalid JSON input\n"],
      [] => ["", 2, "Usage: jmespath [--pretty] [--file PATH] (EXPRESSION | --query-file PATH)\n       " \
                    "jmespath --validate (EXPRESSION | --query-file PATH)\n"]
    }.each do |arguments, (input, expected_status, expected_errors)|
      it "reports #{arguments.inspect} failures through #{name}" do
        output, errors, status = Open3.capture3(
          RbConfig.ruby, File.expand_path("../../exe/#{name}", __dir__), *arguments, stdin_data: input
        )
        expect([status.exitstatus, output, errors]).to eq([expected_status, "", expected_errors])
      end
    end

    it "runs the #{name} executable" do
      output, errors, status = Open3.capture3(
        RbConfig.ruby, File.expand_path("../../exe/#{name}", __dir__), "name",
        stdin_data: '{"name":"café"}'
      )
      expect(status).to be_success
      expect(output).to eq("\"café\"\n")
      expect(errors).to be_empty
    end

    {
      "unknown()" => [0, ""],
      "items[?active" => [1, "Expected rbracket, received eof at line 1, column 14\n" \
                             "items[?active\n             ^\n"]
    }.each do |query, (expected_status, expected_errors)|
      it "validates #{query.inspect} through #{name} while stdin remains open" do
        Open3.popen3(RbConfig.ruby, File.expand_path("../../exe/#{name}", __dir__), "--validate", query) do |
          input, output, errors, waiter
        |
          status = Timeout.timeout(5) { waiter.value }
          expect(input).not_to be_closed
          expect([status.exitstatus, output.read, errors.read]).to eq([expected_status, "", expected_errors])
        ensure
          if waiter.alive?
            Process.kill("KILL", waiter.pid)
            waiter.value
          end
        end
      end
    end

    [["--validate"], ["--validate", "@", "extra"]].each do |arguments|
      it "rejects #{arguments.inspect} through #{name}" do
        output, errors, status = Open3.capture3(
          RbConfig.ruby, File.expand_path("../../exe/#{name}", __dir__), *arguments, stdin_data: "invalid JSON"
        )
        expect([status.exitstatus, output, errors]).to eq([2, "", usage])
      end
    end
  end
end
