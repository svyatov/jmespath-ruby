# frozen_string_literal: true

module JMESPath
  # @api private
  module DataAccess
    class << self
      def field(value, name)
        mapping = object(value)
        return nil unless mapping
        return mapping[name] unless mapping[name].nil?

        key = mapping.keys.find { |candidate| candidate.is_a?(Symbol) && candidate.name == name }
        mapping[key] if key
      end

      def array(value)
        convert(value, Array, :to_ary)
      end

      def object(value)
        return value.to_h if value.is_a?(Struct)

        convert(value, Hash, :to_hash)
      end

      def string(value)
        convert(value, String, :to_str)
      end

      private

      def convert(value, type, method)
        return value if value.is_a?(type)
        return nil unless value.respond_to?(method)

        result = value.public_send(method)
        return result if result.nil? || result.is_a?(type)

        raise TypeError, "#{method} must return #{type}"
      end
    end
  end
end
