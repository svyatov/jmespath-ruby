# frozen_string_literal: true

module JMESPath
  class Functions
    # @api private
    module Coercions
      extend self

      def number(value)
        return value if value.is_a?(Integer)
        return value if value.is_a?(Float) && value.finite?

        raise Signature::TypeMismatch.new("Expected a finite number", origin: validation_origin)
      end

      def string(value)
        DataAccess.string(value) || raise(Signature::TypeMismatch.new("Expected a string", origin: validation_origin))
      end

      def array(value)
        DataAccess.array(value) || raise(Signature::TypeMismatch.new("Expected an array", origin: validation_origin))
      end

      def reference(value)
        return value if value.is_a?(ExpressionReference)

        raise Signature::TypeMismatch.new("Expected an expression reference", origin: validation_origin)
      end

      def object(value)
        DataAccess.object(value) || raise(Signature::TypeMismatch.new("Expected an object", origin: validation_origin))
      end

      private

      def validation_origin
        nil
      end
    end
  end
end
