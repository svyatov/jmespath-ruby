# frozen_string_literal: true

module JMESPath
  class Functions
    # @api private
    class JSONValue
      def self.wrap(value)
        case value
        when NilClass, TrueClass, FalseClass, Integer, Float then value
        when String then Kernel.instance_method(:instance_of?).bind_call(value, String) ? value : new(value)
        else new(value)
        end
      end

      def self.key(value)
        case value
        when Symbol then value
        when String then JSONKey.new(value)
        else new(value)
        end
      end

      def initialize(value)
        @value = value
      end

      def to_json(state)
        FailureCapture.application do
          @value.respond_to?(:to_json) ? @value.to_json(state) : state.generate(String.new(@value.to_s))
        end
      end

      def to_s
        FailureCapture.application { @value.to_s }
      end
    end

    # @api private
    class JSONKey < String
      def initialize(value)
        super
        @value = value
      end

      def to_s
        FailureCapture.application { @value.to_s }
      end
    end
  end
end
