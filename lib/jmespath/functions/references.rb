# frozen_string_literal: true

module JMESPath
  class Functions
    # @api private
    module Collections
      class << self
        def map(expression, value, origin: nil)
          reference = Coercions.reference(expression, origin: origin)
          Coercions.array(value, origin: origin).map { |item| reference.call(item) }
        end

        def sort_by(value, expression, origin: nil)
          keyed(value, expression, origin: origin).each_with_index
                                                  .sort_by { |pair, index| [pair.first, index] }
                                                  .map { |pair, _index| pair.last }
        end

        def min_by(value, expression, origin: nil)
          keyed(value, expression, origin: origin).min_by(&:first)&.last
        end

        def max_by(value, expression, origin: nil)
          keyed(value, expression, origin: origin).max_by(&:first)&.last
        end

        def keyed(value, expression, origin: nil)
          reference = Coercions.reference(expression, origin: origin)
          # @type var expected: Symbol?
          expected = nil
          Coercions.array(value, origin: origin).map do |item|
            key = reference.call(item)
            expected = checked_type(key, expected, origin: origin)
            [sort_key(key, origin: origin), item]
          end
        end

        def checked_type(value, expected, origin: nil)
          type = Types.name(value)
          unless %i[number string].include?(type)
            raise Signature::TypeMismatch.new("Expression keys must be numbers or strings", origin: origin)
          end
          if expected && expected != type
            raise Signature::TypeMismatch.new("Expression keys must have one type",
                                              origin: origin)
          end

          type
        end
      end
    end
  end
end
