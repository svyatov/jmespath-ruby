# frozen_string_literal: true

module JMESPath
  class Functions
    # @api private
    module Collections
      SORTABLE_TYPES = %i[number string].freeze

      private

      def map(expression, value, context:)
        reference = reference(expression, context: context, position: 1)
        array(value, context: context, position: 2).map { |item| reference.call(item) }
      end

      def sort_by(value, expression, context:)
        reference = reference(expression, context: context, position: 2)
        # @type var expected: Symbol?
        expected = nil
        # @type var result_context: ValidationContext?
        result_context = nil
        index = 0
        array(value, context: context, position: 1).sort_by do |item|
          key = reference.call(item)
          type = checked_type(key, expected, context: context)
          expected = type
          key_context = result_context || context.with_types([type])
          result_context = key_context
          index += 1
          [sort_key(key, context: key_context, position: 2, stage: :expression_result), index]
        end
      end

      def min_by(value, expression, context:)
        keyed(value, expression, context: context).min_by(&:first)&.last
      end

      def max_by(value, expression, context:)
        keyed(value, expression, context: context).max_by(&:first)&.last
      end

      def keyed(value, expression, context:)
        reference = reference(expression, context: context, position: 2)
        # @type var expected: Symbol?
        expected = nil
        # @type var result_context: ValidationContext?
        result_context = nil
        array(value, context: context, position: 1).map do |item|
          key = reference.call(item)
          type = checked_type(key, expected, context: context)
          expected = type
          key_context = result_context || context.with_types([type])
          result_context = key_context
          [sort_key(key, context: key_context, position: 2, stage: :expression_result), item]
        end
      end

      def checked_type(value, expected, context:)
        type = Types.name(value)
        unless SORTABLE_TYPES.include?(type)
          raise context.type_error(
            "Expression keys must be numbers or strings",
            position: 2, expected_types: expected ? [expected] : SORTABLE_TYPES, actual_type: type,
            origin: validation_origin, stage: :expression_result
          )
        end
        if expected && expected != type
          raise context.type_error(
            "Expression keys must have one type",
            position: 2, expected_types: [expected], actual_type: type,
            origin: validation_origin, stage: :expression_result
          )
        end

        type
      end
    end
  end
end
