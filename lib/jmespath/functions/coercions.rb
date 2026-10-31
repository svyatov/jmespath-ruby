# frozen_string_literal: true

module JMESPath
  class Functions
    # @api private
    module Coercions
      class << self
        def number(value)
          return value if value.is_a?(Integer)
          return value if value.is_a?(Float) && value.finite?

          raise Signature::TypeMismatch, "Expected a finite number"
        end

        def string(value)
          DataAccess.string(value) || raise(Signature::TypeMismatch, "Expected a string")
        end

        def array(value)
          DataAccess.array(value) || raise(Signature::TypeMismatch, "Expected an array")
        end

        def object(value)
          DataAccess.object(value) || raise(Signature::TypeMismatch, "Expected an object")
        end
      end
    end
  end
end
