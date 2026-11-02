# frozen_string_literal: true

module JMESPath
  # Failures reported by the query language.
  module Errors
    # Base class for JMESPath failures.
    class Error < StandardError; end
    # A runtime evaluation failure.
    class RuntimeError < Error; end

    # A required query result is null.
    class NullResultError < RuntimeError
      # @return [String] the frozen query text
      attr_reader :expression

      # @param expression [String] the query that returned null
      # @example Inspect a failed requirement
      #   JMESPath::Errors::NullResultError.new(expression: "user.name").expression #=> "user.name"
      def initialize(expression:)
        @expression = expression.dup.freeze
        super("Expression returned null")
      end
    end

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
    # @example Inspect a validation failure
    #   error = begin
    #     JMESPath.search("length(@)", 4)
    #   rescue JMESPath::Errors::InvalidTypeError => failure
    #     failure
    #   end
    #   error.expected_types #=> [:string, :array, :object]
    #   error.argument_position #=> 1
    class InvalidTypeError < RuntimeError
      include FunctionFailure

      # @!attribute [r] function_name
      #   @return [String, nil] function identifier
      # @!attribute [r] signature
      #   @return [Array<Array<Symbol>>, nil] complete declared signature
      # @!attribute [r] source_range
      #   @return [Range<Integer>, nil] exclusive byte range of the function call
      # @!method variadic?
      #   @return [Boolean, nil] whether the last declared argument repeats

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

      # @!attribute [r] function_name
      #   @return [String, nil] function identifier
      # @!attribute [r] signature
      #   @return [Array<Array<Symbol>>, nil] complete declared signature
      # @!attribute [r] source_range
      #   @return [Range<Integer>, nil] exclusive byte range of the function call
      # @!method variadic?
      #   @return [Boolean, nil] whether the last declared argument repeats

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
    class UnknownFunctionError < RuntimeError
      # @return [String, nil] unregistered function identifier
      attr_reader :function_name
      # @return [Array<String>] up to three similar names from the active registry
      attr_reader :suggestions

      # @param message [String, nil] failure message
      # @param function_name [String, nil] unregistered function identifier
      # @param suggestions [Array<String>] ranked registered names
      def initialize(message = nil, function_name: nil, suggestions: [])
        @function_name = function_name&.dup&.freeze
        @suggestions = suggestions.map { |name| name.dup.freeze }.freeze
        message = "#{message}. Did you mean #{@suggestions.join(', ')}?" unless @suggestions.empty?
        super(message)
      end
    end
  end
end
