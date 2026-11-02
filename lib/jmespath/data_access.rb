# frozen_string_literal: true

module JMESPath
  # @api private
  module DataAccess
    # @api private
    module FieldLookup
      def field(value, name = @field_name)
        mapping = value.is_a?(Hash) ? value : DataAccess.object(value)
        return nil unless mapping

        FailureCapture.application do
          result = mapping[name]
          return result unless result.nil?

          mapping.each_key do |key|
            return mapping[key] if key.is_a?(Symbol) && key.name == name
          end
          nil
        end
      end
    end

    extend FieldLookup

    # @api private
    class FieldReader
      include FieldLookup

      def initialize(name)
        @field_name = name
        freeze
      end

      alias call field

      private :field
    end

    class << self
      def array(value)
        convert(value, Array, :to_ary)
      end

      def object(value)
        return FailureCapture.application { value.to_h } if value.is_a?(Struct)

        convert(value, Hash, :to_hash)
      end

      def string(value)
        convert(value, String, :to_str)
      end

      private

      def convert(value, type, method)
        return value if value.is_a?(type)

        result = FailureCapture.application do
          value.public_send(method) if value.respond_to?(method)
        end
        return result if result.nil? || result.is_a?(type)

        raise TypeError, "#{method} must return #{type}"
      end
    end
  end
end
