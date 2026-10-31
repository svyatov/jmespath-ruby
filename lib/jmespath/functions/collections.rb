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

      def sum(value)
        array(value).sum { |item| number(item) }
      end

      def avg(value)
        values = array(value)
        number(sum(value)).fdiv(values.length) unless values.empty?
      end

      def min(value)
        array(value).min_by { |item| sort_key(item) }
      end

      def max(value)
        array(value).max_by { |item| sort_key(item) }
      end

      def sort(value)
        array(value).each_with_index.sort_by do |item, index|
          [sort_key(item), index]
        end.map(&:first)
      end

      def join(separator, value)
        array(value).map do |item|
          string(item)
        end.join(string(separator))
      end

      def keys(value)
        object(value).keys.map(&:to_s)
      end

      def values(value)
        object(value).values
      end

      def merge(*values)
        # @type var result: Hash[value, value]
        result = {}
        values.each { |value| result.merge!(object(value)) }
        result
      end

      def sort_key(value)
        DataAccess.string(value) || number(value)
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
