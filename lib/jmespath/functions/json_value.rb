# frozen_string_literal: true

module JMESPath
  class Functions
    # @api private
    class JSONValue
      def self.wrap(value)
        case value
        when NilClass, TrueClass, FalseClass, String, Integer, Float then value
        else new(value)
        end
      end

      def initialize(value)
        @value = value
      end

      def to_json(state)
        FailureCapture.application do
          @value.respond_to?(:to_json) ? @value.to_json(state) : @value.to_s.to_json(state)
        end
      end
    end
  end
end
