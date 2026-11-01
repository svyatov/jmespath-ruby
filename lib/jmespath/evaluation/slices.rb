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

      @forward = @step.positive?
    end

    def apply(values)
      length = values.length
      index = bound(@start, length, @forward ? 0 : length - 1)
      stop = bound(@stop, length, @forward ? length : -1)
      # @type var result: Array[value]
      result = []
      while @forward ? index < stop : index > stop
        result << values[index]
        index += @step
      end
      result
    end

    private

    def bound(value, length, fallback)
      return fallback if value.nil?

      index = value.negative? ? value + length : value
      @forward ? index.clamp(0, length) : index.clamp(-1, length - 1)
    end
  end
end
