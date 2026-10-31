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
            result.with_builtin(name, signature: signature, variadic: name == "merge") do |origin, *args|
              send(name, *args, origin: origin)
            end
          end
        end

        def sum(value, origin: nil)
          Coercions.array(value, origin: origin).sum { |item| Coercions.number(item, origin: origin) }
        end

        def avg(value, origin: nil)
          values = Coercions.array(value, origin: origin)
          Coercions.number(sum(value, origin: origin), origin: origin).fdiv(values.length) unless values.empty?
        end

        def min(value, origin: nil)
          Coercions.array(value, origin: origin).min_by { |item| sort_key(item, origin: origin) }
        end

        def max(value, origin: nil)
          Coercions.array(value, origin: origin).max_by { |item| sort_key(item, origin: origin) }
        end

        def sort(value, origin: nil)
          Coercions.array(value, origin: origin).each_with_index.sort_by do |item, index|
            [sort_key(item, origin: origin), index]
          end.map(&:first)
        end

        def join(separator, value, origin: nil)
          Coercions.array(value, origin: origin).map do |item|
            Coercions.string(item, origin: origin)
          end.join(Coercions.string(separator, origin: origin))
        end

        def keys(value, origin: nil)
          Coercions.object(value, origin: origin).keys.map(&:to_s)
        end

        def values(value, origin: nil)
          Coercions.object(value, origin: origin).values
        end

        def merge(*values, origin: nil)
          # @type var result: Hash[value, value]
          result = {}
          values.each { |value| result.merge!(Coercions.object(value, origin: origin)) }
          result
        end

        def sort_key(value, origin: nil)
          DataAccess.string(value) || Coercions.number(value, origin: origin)
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
