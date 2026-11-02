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
        DataAccess.string(value) || JSON.generate(normalize_json(value))
      rescue JSON::NestingError => e
        raise if FailureCapture.excluded?(e)

        raise FailureCapture.owned(Errors::InvalidValueError.new("Value is too deeply nested to serialize"))
      end

      def normalize_json(value)
        return Types.normalize(value) unless FailureCapture.active?

        Normalizer.new { |scalar| JSONValue.wrap(scalar) }.call(value)
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

require_relative "json_value"
