# frozen_string_literal: true

module JMESPath
  # @api private
  class Evaluator
    private

    def slice(node, data)
      values = DataAccess.array(evaluate(node.children.fetch(0), data))
      return nil unless values

      start, stop, step = Array(node.value).map { |part| part.nil? ? nil : Integer(part) }
      Slice.new(start: start, stop: stop, step: step).apply(values)
    end
  end

  # @api private
  class Slice
    def initialize(start:, stop:, step:)
      @start = start
      @stop = stop
      @step = step || 1
      raise Errors::InvalidValueError, "Slice step cannot be zero" if @step.zero?
    end

    def apply(values)
      index = bound(@start, values.length, @step.positive? ? 0 : values.length - 1)
      stop = bound(@stop, values.length, @step.positive? ? values.length : -1)
      # @type var result: Array[value]
      result = []
      while @step.positive? ? index < stop : index > stop
        result << values[index]
        index += @step
      end
      result
    end

    private

    def bound(value, length, fallback)
      return fallback if value.nil?

      index = value.negative? ? value + length : value
      @step.positive? ? index.clamp(0, length) : index.clamp(-1, length - 1)
    end
  end
end
