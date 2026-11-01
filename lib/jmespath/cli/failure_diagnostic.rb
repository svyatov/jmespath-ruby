# frozen_string_literal: true

module JMESPath
  module CLI
    # @api private
    module FailureDiagnostic
      class << self
        def format(error, expression)
          return JMESPath::Diagnostic.format(error) if error.is_a?(Errors::SyntaxError)

          position = source_position(error, expression)
          diagnostic = if position
                         Errors::SyntaxError.new(message(error), expression: expression || "", position: position)
                       else
                         Errors::SyntaxError.new(message(error))
                       end
          JMESPath::Diagnostic.format(diagnostic)
        end

        private

        def message(error)
          return "Invalid JSON input" if error.is_a?(JSON::ParserError)

          details = case error
                    when Errors::InvalidTypeError then type_message(error)
                    when Errors::InvalidArityError then arity_message(error)
                    end
          details || error.message
        end

        def type_message(error)
          subject = type_subject(error)
          types = error.expected_types
          actual = error.actual_type
          return unless subject && types && actual
          return if types.empty?

          "#{subject}: expected #{expected_types(types)}; received #{type_name(actual)}"
        end

        def type_subject(error)
          name = error.function_name
          position = error.argument_position
          return unless name && position&.positive?

          case error.validation_stage
          when :argument then "Invalid argument #{position} for #{name}"
          when :expression_result then "Invalid expression result for argument #{position} of #{name}"
          end
        end

        def arity_message(error)
          name = error.function_name
          expected = error.expected_arity
          actual = error.actual_arity
          return unless name && expected && actual
          return if expected.negative? || actual.negative?

          count = arity_count(expected, error.variadic?)
          return unless count

          "Invalid number of arguments for #{name}: expected #{count}; received #{actual}"
        end

        def arity_count(expected, variadic)
          return if variadic.nil?

          variadic ? "at least #{expected}" : expected.to_s
        end

        def expected_types(types)
          names = types.map { |type| type_name(type) }
          return names.join(" or ") if names.length < 3

          "#{names.take(names.length - 1).join(', ')}, or #{names.last}"
        end

        def type_name(type)
          case type
          when :array_string then "array of strings"
          when :array_number then "array of numbers"
          else type.to_s
          end
        end

        def source_position(error, expression)
          return unless expression&.valid_encoding?
          return unless error.is_a?(Errors::InvalidTypeError) || error.is_a?(Errors::InvalidArityError)

          range = error.source_range
          range.begin if range && valid_range?(range, expression)
        end

        def valid_range?(range, expression)
          start = range.begin
          finish = range.end
          return false unless start && finish && range.exclude_end?
          return false unless valid_bounds?(start, finish, expression)

          expression.byteslice(0, start).to_s.valid_encoding? && expression.byteslice(0, finish).to_s.valid_encoding?
        end

        def valid_bounds?(start, finish, expression)
          start >= 0 && finish > start && finish <= expression.bytesize
        end
      end
    end
  end
end
