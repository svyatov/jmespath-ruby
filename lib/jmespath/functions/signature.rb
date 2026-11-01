# frozen_string_literal: true

module JMESPath
  class Functions
    # @api private
    class Signature
      TYPES = %i[any null boolean number string array object expref array_number array_string].freeze

      attr_reader :arguments, :variadic

      # Identifies the invocation that created a validation failure.
      module FailureOrigin
        attr_reader :origin

        def initialize(message = nil, origin: nil, **metadata)
          @origin = origin
          super(message, **metadata)
        end
      end

      # An error raised by the library's argument validator.
      class TypeMismatch < Errors::InvalidTypeError
        include FailureOrigin
      end

      # An error raised by the library's arity validator.
      class ArityMismatch < Errors::InvalidArityError
        include FailureOrigin
      end

      attr_reader :arguments

      def variadic?
        @variadic
      end

      def initialize(arguments, variadic: false)
        raise ArgumentError, "Invalid function signature" unless valid_definition?(arguments)
        raise ArgumentError, "Variadic signatures require an argument" if variadic && arguments.empty?

        @arguments = arguments.map { |types| types.dup.freeze }.freeze
        @variadic = variadic
        freeze
      end

      def validate!(values, name, origin: nil, context: nil)
        context ||= ValidationContext.new(name, self)
        unless valid_arity?(values.length)
          raise context.arity_error("Invalid number of arguments for #{name}", actual_arity: values.length,
                                                                               origin: origin)
        end

        values.each_with_index do |value, index|
          types = @arguments.fetch(index) { @arguments.fetch(-1) }
          next if types.any? { |type| matches?(value, type) }

          reject_type!(value, index, types, name, origin, context)
        end
      end

      private

      def reject_type!(value, index, types, name, origin, context) # rubocop:disable Metrics/ParameterLists
        actual_type = Types.name(value)
        raise context.type_error("Invalid argument #{index + 1} for #{name}: #{actual_type}",
                                 position: index + 1, expected_types: types, actual_type: actual_type, origin: origin)
      end

      def valid_definition?(arguments)
        arguments.is_a?(Array) && arguments.all? do |types|
          types.is_a?(Array) && !types.empty? && (types - TYPES).empty?
        end
      end

      def valid_arity?(count)
        @variadic ? count >= @arguments.length : count == @arguments.length
      end

      def matches?(value, type)
        return true if type == :any
        return array_matches?(value, :number) if type == :array_number
        return array_matches?(value, :string) if type == :array_string

        Types.name(value) == type
      end

      def array_matches?(value, type)
        array = DataAccess.array(value)
        array&.all? { |item| Types.name(item) == type }
      end
    end
  end
end
