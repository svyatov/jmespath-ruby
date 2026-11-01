# frozen_string_literal: true

module JMESPath
  class Functions
    # @api private
    class FunctionCall
      include Scalar
      include Collections
      include Coercions

      private :number, :string, :array, :reference, :object

      def call(definition, name, arguments, disable_visit_errors: false)
        definition.signature.validate!(arguments, name, origin: self)
        implementation = definition.implementation
        implementation.is_a?(Symbol) ? send(implementation, *arguments) : implementation.call(*arguments)
      rescue Signature::TypeMismatch, Signature::ArityMismatch => e
        raise unless disable_visit_errors && e.origin.equal?(self)

        nil
      end

      STRICT = new.freeze

      private

      def validation_origin
        self
      end
    end
  end
end
