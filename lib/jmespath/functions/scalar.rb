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

      def self.register(registry)
        SIGNATURES.reduce(registry) do |result, (name, signature)|
          handler = %w[contains ends_with starts_with].include?(name) ? "#{name}?" : name
          result.with_builtin(name, signature: signature, handler: handler.to_sym, variadic: name == "not_null")
        end
      end

      private

      def abs(value, context:)
        number(value, context: context, position: 1).abs
      end

      def ceil(value, context:)
        number(value, context: context, position: 1).ceil
      end

      def floor(value, context:)
        number(value, context: context, position: 1).floor
      end

      def contains?(subject, search, context:)
        text = DataAccess.string(subject)
        return text.include?(string(search, context: context, position: 2)) if text

        array(subject, context: context, position: 1).any? { |item| Types.equal?(item, search) }
      end

      def ends_with?(text, suffix, context:)
        string(text, context: context, position: 1).end_with?(string(suffix, context: context, position: 2))
      end

      def starts_with?(text, prefix, context:)
        string(text, context: context, position: 1).start_with?(string(prefix, context: context, position: 2))
      end

      def length(value, context:)
        collection = DataAccess.string(value) || DataAccess.array(value) || object(value, context: context, position: 1)
        collection.length
      end

      def reverse(value, context:)
        (DataAccess.string(value) || array(value, context: context, position: 1)).reverse
      end

      def type(value, **)
        name = Types.name(value)
        name.to_s unless name == :unknown
      end

      def not_null(*values, **)
        values.find { |value| !value.nil? }
      end
    end
  end
end

require_relative "coercions"
require_relative "conversion"
