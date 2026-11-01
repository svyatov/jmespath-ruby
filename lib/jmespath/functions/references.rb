# frozen_string_literal: true

module JMESPath
  class Functions
    # @api private
    module Collections
      SORTABLE_TYPES = %i[number string].freeze

      private

      def map(expression, value)
        reference = reference(expression)
        array(value).map { |item| reference.call(item) }
      end

      def sort_by(value, expression)
        reference = reference(expression)
        # @type var expected: Symbol?
        expected = nil
        index = 0
        array(value).sort_by do |item|
          key = reference.call(item)
          expected = checked_type(key, expected)
          index += 1
          [sort_key(key), index]
        end
      end

      def min_by(value, expression)
        keyed(value, expression).min_by(&:first)&.last
      end

      def max_by(value, expression)
        keyed(value, expression).max_by(&:first)&.last
      end

      def keyed(value, expression)
        reference = reference(expression)
        # @type var expected: Symbol?
        expected = nil
        array(value).map do |item|
          key = reference.call(item)
          expected = checked_type(key, expected)
          [sort_key(key), item]
        end
      end

      def checked_type(value, expected)
        type = Types.name(value)
        unless SORTABLE_TYPES.include?(type)
          raise Signature::TypeMismatch.new("Expression keys must be numbers or strings", origin: validation_origin)
        end
        if expected && expected != type
          raise Signature::TypeMismatch.new("Expression keys must have one type",
                                            origin: validation_origin)
        end

        type
      end
    end
  end
end
