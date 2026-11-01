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
      # @return [String] the reason parsing failed, without coordinates
      attr_reader :reason
      # @return [String] the expression text
      attr_reader :expression
      # @return [Integer] zero-based byte offset
      attr_reader :position

      # @param message [String] the reason parsing failed
      # @param expression [String] expression text
      # @param position [Integer] zero-based byte offset
      def initialize(message, expression: "", position: nil)
        @reason = message.dup.freeze
        @expression = expression.dup.freeze
        @location_known = !position.nil?
        @position = position || 0
        super("#{message} at byte #{@position}")
      end

      # @return [Boolean] whether the caller supplied a source position
      def location_known?
        @location_known
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

    # @api private
    module FunctionFailure
      # @return [String, nil] function identifier
      attr_reader :function_name
      # @return [Array<Array<Symbol>>, nil] complete declared signature
      attr_reader :signature
      # @return [Range<Integer>, nil] exclusive byte range of the function call
      attr_reader :source_range

      # @api private
      def initialize(message = nil, function_name: nil, signature: nil, variadic: nil, source_range: nil)
        @function_name = function_name.dup.freeze
        @signature = signature&.map { |types| types.dup.freeze }&.freeze
        @variadic = variadic
        @source_range = source_range.dup.freeze
        super(message)
      end

      # @return [Boolean, nil] whether the last declared argument repeats
      def variadic?
        @variadic
      end
    end

    # A function received an unsupported value type.
    class InvalidTypeError < RuntimeError
      include FunctionFailure

      # @return [Integer, nil] one-based actual argument position
      attr_reader :argument_position
      # @return [Array<Symbol>, nil] types accepted by the failing check
      attr_reader :expected_types
      # @return [Symbol, nil] rejected type, including :unknown
      attr_reader :actual_type
      # @return [Symbol, nil] :argument or :expression_result
      attr_reader :validation_stage

      # @api private
      def initialize(message = nil, argument_position: nil, expected_types: nil, actual_type: nil, # rubocop:disable Metrics/ParameterLists
                     validation_stage: nil, **context)
        @argument_position = argument_position
        @expected_types = expected_types&.dup&.freeze
        @actual_type = actual_type
        @validation_stage = validation_stage
        super(message, **context)
      end
    end

    # A value is invalid for the requested operation.
    class InvalidValueError < RuntimeError; end

    # A function received an incorrect number of arguments.
    class InvalidArityError < RuntimeError
      include FunctionFailure

      # @return [Integer, nil] exact argument count, or minimum when variadic
      attr_reader :expected_arity
      # @return [Integer, nil] actual argument count
      attr_reader :actual_arity

      # @api private
      def initialize(message = nil, expected_arity: nil, actual_arity: nil, **context)
        @expected_arity = expected_arity
        @actual_arity = actual_arity
        super(message, **context)
      end
    end

    # A function name is not registered.
    class UnknownFunctionError < RuntimeError; end
  end
end
