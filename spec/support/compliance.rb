# frozen_string_literal: true

require "json"
require_relative "wrappers"

module ComplianceFixtures
  ROOT = File.expand_path("../fixtures/upstream", __dir__)
  BENCHMARK_RESULTS = JSON.parse(File.read(File.expand_path("../benchmarks_expected.json", ROOT)))
  ERRORS = {
    "syntax" => JMESPath::Errors::SyntaxError,
    "invalid-type" => JMESPath::Errors::InvalidTypeError,
    "invalid-value" => JMESPath::Errors::InvalidValueError,
    "invalid-arity" => JMESPath::Errors::InvalidArityError,
    "unknown-function" => JMESPath::Errors::UnknownFunctionError
  }.freeze

  def self.cases
    Dir[File.join(ROOT, "{python,ruby}/{compliance,legacy}/*.json")].flat_map { |path| load_cases(path) }
  end

  def self.load_cases(path)
    JSON.parse(File.read(path)).each_with_index.flat_map do |scenario, group|
      scenario.fetch("cases").each_with_index.map do |item, index|
        entry(path, scenario, item, group, index)
      end
    end
  end

  def self.entry(path, scenario, item, group, index)
    {
      id: "#{path.delete_prefix("#{ROOT}/")}:#{group}:#{index}",
      expression: item.fetch("expression"), given: scenario.fetch("given"),
      result: expected_result(item, group, index), error: item["error"]
    }
  end

  def self.expected_result(item, group, index)
    item.fetch("result") { item.key?("bench") ? BENCHMARK_RESULTS.fetch(group).fetch(index) : nil }
  end

  def self.wrap(value)
    case value
    when Array then Arrayish.new(value.map { |item| wrap(item) })
    when Hash then Hashish.new(value.transform_values { |item| wrap(item) })
    else value
    end
  end

  def assert_compliance(entry, wrapped: false, suppress: false)
    data = wrapped ? ComplianceFixtures.wrap(entry.fetch(:given)) : entry.fetch(:given)
    original = Marshal.dump(data)
    assert_outcome(entry, data, suppress)
    expect(Marshal.dump(data)).to eq(original)
  end

  def assert_outcome(entry, data, suppress)
    if suppress && %w[invalid-type invalid-arity].include?(entry[:error])
      expect(JMESPath.search(entry.fetch(:expression), data, disable_visit_errors: true)).to be_nil
    elsif entry[:error]
      assert_error(entry, data, suppress)
    else
      assert_result(entry, data)
    end
  end

  def assert_error(entry, data, suppress)
    expect { JMESPath.search(entry.fetch(:expression), data, disable_visit_errors: suppress) }
      .to raise_error(ERRORS.fetch(entry.fetch(:error)))
  end

  def assert_result(entry, data)
    result = JMESPath.search(entry.fetch(:expression), data)
    expect(JMESPath::Types.normalize(result)).to eq(entry[:result])
  end
end
