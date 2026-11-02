# frozen_string_literal: true

module JMESPath
  module CLI
    # @api private
    module FunctionListing
      LEGEND = "Types: any accepts any value; A|B accepts either type.\n" \
               "array<T> requires every element to have type T; array is unrestricted.\n" \
               "expref is an expression reference, written &expression.\n" \
               "T... requires one or more arguments of type T.\n" \
               "Signatures describe declared argument types; runtime checks can be narrower.\n"

      def self.render(registry)
        entries = registry.names.map do |name|
          metadata = registry.metadata(name) or raise "Missing function metadata: #{name}"
          "#{name}(#{signature(metadata)}) #{metadata.description}\n"
        end
        "#{entries.join}\n#{LEGEND}"
      end

      class << self
        private

        def signature(metadata)
          metadata.signature.each_with_index.map do |types, index|
            argument(types, metadata.variadic? && index == metadata.signature.length - 1)
          end.join(", ")
        end

        def argument(types, repeated)
          text = types.map { |type| type_name(type) }.join("|")
          return text unless repeated

          text = "(#{text})" if types.length > 1
          "#{text}..."
        end

        def type_name(type)
          case type
          when :array_number then "array<number>"
          when :array_string then "array<string>"
          else type.to_s
          end
        end
      end
    end
  end
end
