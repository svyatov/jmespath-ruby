# frozen_string_literal: true

module JMESPath
  # @api private
  class ExpressionReference
    def initialize(&block)
      @block = block
      freeze
    end

    def call(value)
      @block.call(value)
    end
  end
end
