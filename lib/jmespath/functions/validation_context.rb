# frozen_string_literal: true

module JMESPath
  class Functions
    # @api private
    class ValidationContext
      def initialize(name, signature, source_range: nil, expected_types: nil, actual_type: nil)
        @name = name.dup.freeze
        @signature = signature
        @source_range = source_range&.dup&.freeze
        @expected_types = expected_types&.dup&.freeze
        @actual_type = actual_type
        freeze
      end

      def type_error(message, position:, expected_types:, actual_type:, origin:, stage: :argument) # rubocop:disable Metrics/ParameterLists
        Signature::TypeMismatch.new(
          message,
          **metadata,
          origin: origin, argument_position: position,
          expected_types: @expected_types || expected_types,
          actual_type: @actual_type || actual_type, validation_stage: stage
        )
      end

      def arity_error(message, actual_arity:, origin:)
        Signature::ArityMismatch.new(
          message, **metadata, origin: origin,
                               expected_arity: @signature.arguments.length, actual_arity: actual_arity
        )
      end

      def array_element(position)
        with_types(@signature.arguments.fetch(position - 1), actual_type: :array)
      end

      def with_types(types, actual_type: nil)
        self.class.new(@name, @signature, source_range: @source_range, expected_types: types, actual_type: actual_type)
      end

      private

      def metadata
        { function_name: @name, signature: @signature.arguments, variadic: @signature.variadic?,
          source_range: @source_range }
      end
    end
  end
end
