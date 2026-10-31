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

      def abs(value)
        number(value).abs
      end

      def ceil(value)
        number(value).ceil
      end

      def floor(value)
        number(value).floor
      end

      def contains?(subject, search)
        text = DataAccess.string(subject)
        return text.include?(string(search)) if text

        array(subject).any? { |item| Types.equal?(item, search) }
      end

      def ends_with?(text, suffix)
        string(text).end_with?(string(suffix))
      end

      def starts_with?(text, prefix)
        string(text).start_with?(string(prefix))
      end

      def length(value)
        collection = DataAccess.string(value) || DataAccess.array(value) || object(value)
        collection.length
      end

      def reverse(value)
        (DataAccess.string(value) || array(value)).reverse
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

require_relative "coercions"
require_relative "conversion"
