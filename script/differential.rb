# frozen_string_literal: true

require "optparse"
require "rbconfig"
require_relative "../lib/jmespath"
require_relative "../spec/support/compliance"
require_relative "support/reference_worker"

# Compares semantic cases with both pinned reference libraries.
class DifferentialCheck
  PYTHON = <<~PYTHON
    import json, sys
    sys.path.insert(0, sys.argv[1])
    import jmespath
    errors = {
      "LexerError": "syntax", "ParseError": "syntax",
      "IncompleteExpressionError": "syntax", "EmptyExpressionError": "syntax",
      "JMESPathTypeError": "invalid-type", "ArityError": "invalid-arity",
      "VariadictArityError": "invalid-arity", "UnknownFunctionError": "unknown-function",
      "ValueError": "invalid-value"
    }
    for line in sys.stdin:
      request = json.loads(line)
      try:
        result = {"value": jmespath.search(request["expression"], request["given"])}
      except Exception as error:
        kind = errors.get(type(error).__name__)
        result = {"error": kind} if kind else {"crash": type(error).__name__, "message": str(error)}
      print(json.dumps(result), flush=True)
  PYTHON

  def initialize(python_root, ruby_root)
    script = File.expand_path("support/ruby_reference.rb", __dir__)
    root = File.expand_path("..", __dir__)
    @workers = {
      "implementation" => ReferenceWorker.new([RbConfig.ruby, "-I", "#{root}/lib", script]),
      "ruby" => ReferenceWorker.new([RbConfig.ruby, "-I", "#{ruby_root}/lib", script]),
      "python" => ReferenceWorker.new(["python3", "-c", PYTHON, python_root])
    }
  end

  def run
    cases = (ComplianceFixtures.cases + generated_cases).uniq { |entry| [entry[:expression], entry[:given]] }
    differences = cases.filter_map { |entry| compare(entry) }
    approved, unexpected = differences.partition { |entry| entry[:approved] }
    { checked_cases: cases.length, approved_differences: approved, differences: unexpected }
  ensure
    @workers.each_value(&:close)
  end

  private

  def compare(entry)
    expected = entry[:error] ? { "error" => entry[:error] } : { "value" => entry[:result] }
    payload = { "expression" => entry[:expression], "given" => entry[:given] }
    results = @workers.transform_values { |worker| worker.request(payload) }
    return nil if results.values.all? { |value| value == expected }

    { id: entry[:id], request: payload, expected: expected, results: results,
      approved: approved?(entry, expected, results) }
  end

  def approved?(entry, expected, results)
    ids = %w[python/compliance/functions.json:2:15 python/compliance/functions.json:2:21]
    ids.include?(entry[:id]) && results["implementation"] == expected &&
      results["python"] == expected && results["ruby"] == { "error" => "invalid-type" }
  end

  def generated_cases
    100.times.map do |index|
      {
        id: "generated/filter/#{index}",
        expression: "items[?n > #{96.chr}#{index}#{96.chr}].n",
        given: { "items" => (index..(index + 6)).map { |number| { "n" => number } } },
        result: ((index + 1)..(index + 6)).to_a
      }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |parser|
    parser.on("--python-root PATH") { |value| options[:python] = value }
    parser.on("--ruby-root PATH") { |value| options[:ruby] = value }
    parser.on("--output PATH") { |value| options[:output] = value }
  end.parse!
  report = DifferentialCheck.new(options.fetch(:python), options.fetch(:ruby)).run
  File.write(options[:output], "#{JSON.pretty_generate(report)}\n") if options[:output]
  puts JSON.generate(checked_cases: report[:checked_cases], approved_differences: report[:approved_differences].length,
                     unexpected_differences: report[:differences].length)
  exit(report[:differences].empty? ? 0 : 1)
end
