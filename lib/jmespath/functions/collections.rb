# frozen_string_literal: true

module JMESPath
  # Standard and custom function definitions.
  class Functions
    # @api private
    module Collections
      SIGNATURES = {
        "avg" => [[:array_number]], "sum" => [[:array_number]],
        "min" => [%i[array_number array_string]], "max" => [%i[array_number array_string]],
        "sort" => [%i[array_number array_string]], "join" => [[:string], [:array_string]],
        "keys" => [[:object]], "values" => [[:object]], "merge" => [[:object]],
        "map" => [[:expref], [:array]], "sort_by" => [[:array], [:expref]],
        "min_by" => [[:array], [:expref]], "max_by" => [[:array], [:expref]]
      }.freeze

      def self.register(registry)
        SIGNATURES.reduce(registry) do |result, (name, signature)|
          result.with_builtin(name, signature: signature, handler: name.to_sym, variadic: name == "merge")
        end
      end

      private

      def sum(value, context:)
        element_context = context.array_element(1)
        array(value, context: context, position: 1).sum { |item| number(item, context: element_context, position: 1) }
      end

      def avg(value, context:)
        values = array(value, context: context, position: 1)
        return if values.empty?

        number(sum(value, context: context), context: context.array_element(1), position: 1).fdiv(values.length)
      end

      def min(value, context:)
        element_context = context.array_element(1)
        array(value, context: context, position: 1).min_by { |item| sort_key(item, context: element_context) }
      end

      def max(value, context:)
        element_context = context.array_element(1)
        array(value, context: context, position: 1).max_by { |item| sort_key(item, context: element_context) }
      end

      def sort(value, context:)
        element_context = context.array_element(1)
        array(value, context: context, position: 1).each_with_index.sort_by do |item, index|
          [sort_key(item, context: element_context), index]
        end.map(&:first)
      end

      def join(separator, value, context:)
        element_context = context.array_element(2)
        array(value, context: context, position: 2).map do |item|
          string(item, context: element_context, position: 2)
        end.join(string(separator, context: context, position: 1))
      end

      def keys(value, context:)
        object(value, context: context, position: 1).keys.map(&:to_s)
      end

      def values(value, context:)
        object(value, context: context, position: 1).values
      end

      def merge(*values, context:)
        # @type var result: Hash[value, value]
        result = {}
        values.each_with_index { |value, index| result.merge!(object(value, context: context, position: index + 1)) }
        result
      end

      def sort_key(value, context:, position: 1, stage: :argument)
        DataAccess.string(value) || number(value, context: context, position: position, stage: stage)
      end
    end

    # @api private
    DEFAULT = Collections.register(Scalar.register(new))

    # @return [Functions] immutable standard function definitions
    def self.default
      DEFAULT
    end
  end
end

require_relative "references"
