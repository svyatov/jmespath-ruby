# frozen_string_literal: true

module JMESPath
  # @api private
  module Types
    class << self
      def name(value)
        return :null if value.nil?
        return :boolean if value.equal?(true) || value.equal?(false)
        return :number if number?(value)
        return :expref if value.is_a?(ExpressionReference)

        collection_name(value)
      end

      def number?(value)
        value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
      end

      def falsey?(value)
        return true if value.nil? || value.equal?(false)

        collection = DataAccess.string(value) || DataAccess.array(value) || DataAccess.object(value)
        collection ? collection.empty? : false
      end

      def equal?(left, right)
        normalize(left) == normalize(right)
      end

      def normalize(value, active = {})
        list = DataAccess.array(value)
        return guarded(value, active) { list.map { |item| normalize(item, active) } } if list

        mapping = DataAccess.object(value)
        return guarded(value, active) { mapping.transform_values { |item| normalize(item, active) } } if mapping

        DataAccess.string(value) || value
      end

      private

      def collection_name(value)
        return :string if DataAccess.string(value)
        return :array if DataAccess.array(value)
        return :object if DataAccess.object(value)

        :unknown
      end

      def guarded(value, active)
        id = value.object_id
        raise Errors::InvalidValueError, "Cyclic values cannot be compared or serialized" if active[id]

        active[id] = true
        begin
          yield
        ensure
          active.delete(id)
        end
      end
    end
  end
end
