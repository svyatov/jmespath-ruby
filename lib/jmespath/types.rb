# frozen_string_literal: true

module JMESPath
  # @api private
  module Types
    class << self
      def name(value)
        case value
        when Integer then :number
        when String then :string
        when NilClass then :null
        when TrueClass, FalseClass then :boolean
        else other_name(value)
        end
      end

      def number?(value)
        value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
      end

      def falsey?(value)
        return true if value.nil? || value.equal?(false)
        return false if value.equal?(true)

        collection = DataAccess.string(value) || DataAccess.array(value) || DataAccess.object(value)
        collection ? collection.empty? : false
      end

      def equal?(left, right)
        pending = [[normalize(left), normalize(right)]]
        while (pair = pending.pop)
          return false unless matching?(pair.fetch(0), pair.fetch(1), pending)
        end
        true
      end

      def normalize(value)
        Normalizer.new.call(value)
      end

      private

      def other_name(value)
        return :number if number?(value)
        return :expref if value.is_a?(ExpressionReference)

        collection_name(value)
      end

      def collection_name(value)
        return :string if DataAccess.string(value)
        return :array if DataAccess.array(value)
        return :object if DataAccess.object(value)

        :unknown
      end

      def matching?(left, right, pending)
        case left
        when Array then arrays_match?(left, right, pending)
        when Hash then objects_match?(left, right, pending)
        else left == right
        end
      end

      def arrays_match?(left, right, pending)
        return false unless right.is_a?(Array) && left.length == right.length

        left.each_with_index { |value, index| pending << [value, right[index]] }
        true
      end

      def objects_match?(left, right, pending)
        return false unless right.is_a?(Hash) && left.length == right.length
        return false unless left.each_key.all? { |key| right.key?(key) }

        left.each { |key, value| pending << [value, right[key]] }
        true
      end
    end
  end
end

require_relative "normalizer"
