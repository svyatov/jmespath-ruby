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
            result.with(name, signature: signature, variadic: name == "not_null") { |*args| send(handler, *args) }
          end
        end

        def abs(value)
          Coercions.number(value).abs
        end

        def ceil(value)
          Coercions.number(value).ceil
        end

        def floor(value)
          Coercions.number(value).floor
        end

        def contains?(subject, search)
          text = DataAccess.string(subject)
          return text.include?(Coercions.string(search)) if text

          Coercions.array(subject).any? { |item| Types.equal?(item, search) }
        end

        def ends_with?(text, suffix)
          Coercions.string(text).end_with?(Coercions.string(suffix))
        end

        def starts_with?(text, prefix)
          Coercions.string(text).start_with?(Coercions.string(prefix))
        end

        def length(value)
          collection = DataAccess.string(value) || DataAccess.array(value) || Coercions.object(value)
          collection.length
        end

        def reverse(value)
          (DataAccess.string(value) || Coercions.array(value)).reverse
        end

        def type(value)
          name = Types.name(value)
          name.to_s unless name == :unknown
        end

        def not_null(*values)
          values.find { |value| !value.nil? }
        end
      end
    end
  end
end

require_relative "coercions"
require_relative "conversion"
