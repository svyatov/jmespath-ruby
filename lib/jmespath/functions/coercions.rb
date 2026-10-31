# frozen_string_literal: true

module JMESPath
  class Functions
    # @api private
    module Coercions
      class << self
        def number(value, origin: nil)
          return value if value.is_a?(Integer)
          return value if value.is_a?(Float) && value.finite?

          raise Signature::TypeMismatch.new("Expected a finite number", origin: origin)
        end

        def string(value, origin: nil)
          DataAccess.string(value) || raise(Signature::TypeMismatch.new("Expected a string", origin: origin))
        end

        def array(value, origin: nil)
          DataAccess.array(value) || raise(Signature::TypeMismatch.new("Expected an array", origin: origin))
        end

        def reference(value, origin: nil)
          return value if value.is_a?(ExpressionReference)

          raise Signature::TypeMismatch.new("Expected an expression reference", origin: origin)
        end

        def object(value, origin: nil)
          DataAccess.object(value) || raise(Signature::TypeMismatch.new("Expected an object", origin: origin))
        end
      end
    end
  end
end
