# frozen_string_literal: true

module JMESPath
  # Failures reported by the query language.
  module Errors
    # Base class for JMESPath failures.
    class Error < StandardError; end
    # A runtime evaluation failure.
    class RuntimeError < Error; end

    # A malformed expression with a byte position and readable coordinates.
    class SyntaxError < Error
      # @return [String] the expression text
      attr_reader :expression
      # @return [Integer] zero-based byte offset
      attr_reader :position

      # @param message [String] the reason parsing failed
      # @param expression [String] expression text
      # @param position [Integer] zero-based byte offset
      def initialize(message, expression: "", position: 0)
        @expression = expression.dup.freeze
        @position = position
        super("#{message} at byte #{position}")
      end

      # @return [Integer] one-based line number
      def line
        prefix.count("\n") + 1
      end

      # @return [Integer] one-based character column
      def column
        (prefix.split("\n", -1).last || "").length + 1
      end

      private

      def prefix
        expression.byteslice(0, position).to_s
      end
    end

    # A function received an unsupported value type.
    class InvalidTypeError < RuntimeError; end
    # A value is invalid for the requested operation.
    class InvalidValueError < RuntimeError; end
    # A function received an incorrect number of arguments.
    class InvalidArityError < RuntimeError; end
    # A function name is not registered.
    class UnknownFunctionError < RuntimeError; end
  end
end
