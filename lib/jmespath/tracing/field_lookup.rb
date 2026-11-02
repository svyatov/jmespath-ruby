# frozen_string_literal: true

module JMESPath
  module Tracing
    # @api private
    module FieldLookup
      def self.call(value, name)
        mapping = value.is_a?(Hash) ? value : DataAccess.object(value)
        return [nil, "non_object"] unless mapping

        result = mapping[name]
        return [result, nil] unless result.nil?

        result, reason = fallback(mapping, name)
        return [result, nil] unless result.nil?

        [nil, native_lookup?(mapping) ? reason : "unknown"]
      end

      def self.fallback(mapping, name)
        present = false
        mapping.each_key do |key|
          return [mapping[key], "null"] if key.is_a?(Symbol) && key.name == name

          # Core checks avoid invoking custom key predicates or equality methods.
          # rubocop:disable-next Style/CaseEquality
          present = true if String === key && String.instance_method(:==).bind_call(key, name)
        end
        [nil, present ? "null" : "missing"]
      end

      def self.native_lookup?(mapping)
        %i[[] each_key].all? do |name|
          Object.instance_method(:method).bind_call(mapping, name).owner == Hash
        end
      end
    end
  end
end
