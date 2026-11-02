# frozen_string_literal: true

module JMESPath
  # Immutable definitions for functions available to an expression.
  class Functions
    # @api private
    Definition = Data.define(:signature, :implementation, :description)

    # Immutable public description of a registered function.
    class Metadata
      # @return [String] function identifier
      attr_reader :name
      # @return [Array<Array<Symbol>>] accepted types for each declared argument
      attr_reader :signature
      # @return [String, nil] optional description
      attr_reader :description

      # @api private
      def initialize(name, signature, variadic, description)
        @name = name.dup.freeze
        @signature = signature.map { |types| types.dup.freeze }.freeze
        @variadic = variadic
        @description = description&.dup&.freeze
        freeze
      end

      # @return [Boolean] whether the final required argument repeats
      def variadic?
        @variadic
      end
    end

    # Create an empty immutable function registry.
    def initialize
      # @type var definitions: Hash[String, Definition]
      definitions = {}
      @definitions = definitions.freeze
      freeze
    end

    # Return an independent registry with one additional definition.
    # @param name [String] unquoted function identifier
    # @param signature [Array<Array<Symbol>>] accepted types for each argument
    # @param variadic [Boolean] repeat the final argument type
    # @param override [Boolean] explicitly replace a definition
    # @param description [String, nil] optional description, replaced on override
    # @yieldparam arguments [Object] evaluated arguments
    # @yieldreturn [Object] the function result
    # @raise [ArgumentError] the definition is invalid or duplicates an existing name
    # @return [Functions] the extended registry
    def with(name, signature:, variadic: false, override: false, description: nil, &block)
      raise ArgumentError, "A function block is required" unless block
      raise ArgumentError, "Invalid function description" unless description.nil? || description.is_a?(String)

      definition = Definition.new(Signature.new(signature, variadic: variadic), block, description&.dup&.freeze)
      add(name, definition, override: override)
    end

    # @api private
    def with_builtin(name, signature:, handler:, description:, variadic: false)
      definition = Definition.new(Signature.new(signature, variadic: variadic), handler, description.dup.freeze)
      add(name, definition, override: false)
    end

    # List names in ascending, case-sensitive lexical order.
    # @return [Array<String>] frozen names in a frozen array
    def names
      @definitions.keys.sort.freeze
    end

    # Inspect a definition without executing its implementation.
    # @param name [String] function identifier
    # @return [Metadata, nil] immutable metadata, or nil if absent
    def metadata(name)
      definition = @definitions[name]
      return unless definition

      signature = definition.signature
      Metadata.new(name, signature.arguments, signature.variadic?, definition.description)
    end

    # Evaluate a registered function with checked arguments.
    # @param name [String] function identifier
    # @param arguments [Array<Object>] evaluated values
    # @param disable_visit_errors [Boolean] return nil for validation failures
    # @return [Object] the callback result
    # @raise [Errors::UnknownFunctionError] the name is absent
    # @raise [Errors::InvalidTypeError] argument types are incompatible
    # @raise [Errors::InvalidArityError] the number of arguments is invalid
    def call(name, arguments, disable_visit_errors: false)
      FailureCapture.application { invoke(name, arguments, disable_visit_errors: disable_visit_errors) }
    end

    # @api private
    def call_with_context(name, arguments, source_range:, disable_visit_errors: nil)
      # Preserve compiled keyword omission separately from the evaluator's explicit false.
      unless method(:call).owner.equal?(Functions)
        return FailureCapture.application do
          if disable_visit_errors.nil?
            call(name, arguments)
          else
            call(name, arguments, disable_visit_errors: disable_visit_errors)
          end
        end
      end

      invoke(name, arguments, source_range: source_range, disable_visit_errors: !!disable_visit_errors)
    end

    # @api private
    def definition(name)
      @definitions[name]
    end

    private

    def invoke(name, arguments, disable_visit_errors:, source_range: nil)
      definition = @definitions.fetch(name) do
        raise FailureCapture.owned(
          Errors::UnknownFunctionError.new("Unknown function: #{name}", function_name: name,
                                                                        suggestions: Suggestions.for(name, names))
        )
      end
      context = ValidationContext.new(name, definition.signature, source_range: source_range)
      invocation = disable_visit_errors ? FunctionCall.new : FunctionCall::STRICT
      invocation.call(definition, name, arguments, disable_visit_errors: disable_visit_errors, context: context)
    end

    def add(name, definition, override:)
      unless name.is_a?(String) && name.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
        raise ArgumentError, "Invalid function name"
      end
      raise ArgumentError, "Function #{name} is already registered" if @definitions.key?(name) && !override

      result = dup
      result.instance_variable_set(:@definitions, @definitions.merge(name.dup.freeze => definition).freeze)
      result.freeze
    end
  end
end

require_relative "functions/signature"
require_relative "functions/validation_context"
