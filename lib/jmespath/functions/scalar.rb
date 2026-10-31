# frozen_string_literal: true

module JMESPath
  class Functions
    # @api private
    module Scalar
      SIGNATURES = {
        "abs" => [[:number]], "ceil" => [[:number]], "floor" => [[:number]],
        "contains" => [%i[array string], [:any]],
        "ends_with" => [[:string], [:string]], "starts_with" => [[:string], [:string]],
        "length" => [%i[string array object]], "reverse" => [%i[string array]],
        "type" => [[:any]], "to_array" => [[:any]], "to_string" => [[:any]],
        "to_number" => [[:any]], "not_null" => [[:any]]
      }.freeze

      class << self
        def register(registry)
          SIGNATURES.reduce(registry) do |result, (name, signature)|
            handler = %w[contains ends_with starts_with].include?(name) ? "#{name}?" : name
            result.with_builtin(name, signature: signature, variadic: name == "not_null") do |origin, *args|
              send(handler, *args, origin: origin)
            end
          end
        end

        def abs(value, origin: nil)
          Coercions.number(value, origin: origin).abs
        end

        def ceil(value, origin: nil)
          Coercions.number(value, origin: origin).ceil
        end

        def floor(value, origin: nil)
          Coercions.number(value, origin: origin).floor
        end

        def contains?(subject, search, origin: nil)
          text = DataAccess.string(subject)
          return text.include?(Coercions.string(search, origin: origin)) if text

          Coercions.array(subject, origin: origin).any? { |item| Types.equal?(item, search) }
        end

        def ends_with?(text, suffix, origin: nil)
          Coercions.string(text, origin: origin).end_with?(Coercions.string(suffix, origin: origin))
        end

        def starts_with?(text, prefix, origin: nil)
          Coercions.string(text, origin: origin).start_with?(Coercions.string(prefix, origin: origin))
        end

        def length(value, origin: nil)
          collection = DataAccess.string(value) || DataAccess.array(value) || Coercions.object(value, origin: origin)
          collection.length
        end

        def reverse(value, origin: nil)
          (DataAccess.string(value) || Coercions.array(value, origin: origin)).reverse
        end

        def type(value, **_options)
          name = Types.name(value)
          name.to_s unless name == :unknown
        end

        def not_null(*values, **_options)
          values.find { |value| !value.nil? }
        end
      end
    end
  end
end

require_relative "coercions"
require_relative "conversion"
