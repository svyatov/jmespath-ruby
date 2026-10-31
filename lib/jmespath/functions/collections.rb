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

      class << self
        def register(registry)
          SIGNATURES.reduce(registry) do |result, (name, signature)|
            result.with(name, signature: signature, variadic: name == "merge") { |*args| send(name, *args) }
          end
        end

        def sum(value)
          Coercions.array(value).sum { |item| Coercions.number(item) }
        end

        def avg(value)
          values = Coercions.array(value)
          Coercions.number(sum(value)).fdiv(values.length) unless values.empty?
        end

        def min(value)
          Coercions.array(value).min_by { |item| sort_key(item) }
        end

        def max(value)
          Coercions.array(value).max_by { |item| sort_key(item) }
        end

        def sort(value)
          Coercions.array(value).each_with_index.sort_by { |item, index| [sort_key(item), index] }.map(&:first)
        end

        def join(separator, value)
          Coercions.array(value).map { |item| Coercions.string(item) }.join(Coercions.string(separator))
        end

        def keys(value)
          Coercions.object(value).keys.map(&:to_s)
        end

        def values(value)
          Coercions.object(value).values
        end

        def merge(*values)
          # @type var result: Hash[value, value]
          result = {}
          values.each { |value| result.merge!(Coercions.object(value)) }
          result
        end

        def sort_key(value)
          DataAccess.string(value) || Coercions.number(value)
        end
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
