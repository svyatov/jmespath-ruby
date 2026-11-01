# frozen_string_literal: true

module JMESPath
  class Functions
    # @api private
    module Scalar
      NUMBER = /\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\z/

      private

      def to_array(value, **)
        DataAccess.array(value) || [value]
      end

      def to_string(value, **)
        DataAccess.string(value) || JSON.generate(Types.normalize(value))
      rescue JSON::NestingError
        raise Errors::InvalidValueError, "Value is too deeply nested to serialize"
      end

      def to_number(value, **)
        return value if Types.number?(value)

        text = DataAccess.string(value)&.strip
        return nil unless text && NUMBER.match?(text)

        number = Integer(text, 10, exception: false) || Float(text, exception: false)
        number if Types.number?(number)
      end
    end
  end
end
