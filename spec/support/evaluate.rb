# frozen_string_literal: true

module EvaluationHelper
  def evaluate(source, data, functions: JMESPath::Functions.new)
    node = JMESPath::Parser.new(source).parse
    JMESPath::Evaluator.new(functions: functions).evaluate(node, data)
  end
end

RSpec.configure { |config| config.include EvaluationHelper }
