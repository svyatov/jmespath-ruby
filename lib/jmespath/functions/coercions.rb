# frozen_string_literal: true

module JMESPath
  class Functions
    # @api private
    module Coercions
      extend self

      NATIVE_TYPES = { String => :string, NilClass => :null, TrueClass => :boolean, FalseClass => :boolean,
                       Array => :array, Hash => :object, ExpressionReference => :expref }.freeze

      def number(value, context: nil, position: nil, stage: :argument)
        return value if value.is_a?(Integer)
        return value if value.is_a?(Float) && value.finite?

        raise FailureCapture.owned(type_failure(value, "Expected a finite number", [:number], context, position, stage))
      end

      def string(value, context: nil, position: nil)
        DataAccess.string(value) || raise(FailureCapture.owned(
                                            type_failure(value, "Expected a string", [:string], context, position)
                                          ))
      end

      def array(value, context: nil, position: nil)
        DataAccess.array(value) || raise(FailureCapture.owned(
                                           type_failure(value, "Expected an array", [:array], context, position)
                                         ))
      end

      def reference(value, context: nil, position: nil)
        return value if value.is_a?(ExpressionReference)

        raise FailureCapture.owned(type_failure(value, "Expected an expression reference", [:expref], context,
                                                position))
      end

      def object(value, context: nil, position: nil)
        DataAccess.object(value) || raise(FailureCapture.owned(
                                            type_failure(value, "Expected an object", [:object], context, position)
                                          ))
      end

      private

      def type_failure(value, message, types, context, position, stage = :argument) # rubocop:disable Metrics/ParameterLists
        return Signature::TypeMismatch.new(message, origin: validation_origin) unless context

        context.type_error(message, position: position, expected_types: types, actual_type: native_type(value),
                                    origin: validation_origin, stage: stage)
      end

      def native_type(value)
        return :number if Types.number?(value)

        NATIVE_TYPES.find { |klass, _type| value.is_a?(klass) }&.last || :unknown
      end

      def validation_origin
        nil
      end
    end
  end
end
