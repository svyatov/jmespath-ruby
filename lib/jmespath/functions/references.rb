# frozen_string_literal: true

module JMESPath
  class Functions
    # @api private
    module Collections
      class << self
        def map(expression, value)
          reference = Coercions.reference(expression)
          Coercions.array(value).map { |item| reference.call(item) }
        end

        def sort_by(value, expression)
          keyed(value, expression).each_with_index
                                  .sort_by { |pair, index| [pair.first, index] }
                                  .map { |pair, _index| pair.last }
        end

        def min_by(value, expression)
          keyed(value, expression).min_by(&:first)&.last
        end

        def max_by(value, expression)
          keyed(value, expression).max_by(&:first)&.last
        end

        def keyed(value, expression)
          reference = Coercions.reference(expression)
          # @type var expected: Symbol?
          expected = nil
          Coercions.array(value).map do |item|
            key = reference.call(item)
            expected = checked_type(key, expected)
            [sort_key(key), item]
          end
        end

        def checked_type(value, expected)
          type = Types.name(value)
          unless %i[number string].include?(type)
            raise Signature::TypeMismatch, "Expression keys must be numbers or strings"
          end
          raise Signature::TypeMismatch, "Expression keys must have one type" if expected && expected != type

          type
        end
      end
    end
  end
end
