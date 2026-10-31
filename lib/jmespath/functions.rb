# frozen_string_literal: true

module JMESPath
  # Immutable definitions for functions available to an expression.
  class Functions
    # @api private
    Definition = Data.define(:signature, :implementation)

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
    # @yieldparam arguments [Object] evaluated arguments
    # @yieldreturn [Object] the function result
    # @raise [ArgumentError] the definition is invalid or duplicates an existing name
    # @return [Functions] the extended registry
    def with(name, signature:, variadic: false, override: false, &block)
      raise ArgumentError, "A function block is required" unless block
      raise ArgumentError, "Invalid function name" unless name.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
      raise ArgumentError, "Function #{name} is already registered" if @definitions.key?(name) && !override

      definition = Definition.new(Signature.new(signature, variadic: variadic), block)
      result = dup
      result.instance_variable_set(:@definitions, @definitions.merge(name.dup.freeze => definition).freeze)
      result.freeze
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
      definition = @definitions.fetch(name) { raise Errors::UnknownFunctionError, "Unknown function: #{name}" }
      definition.signature.validate!(arguments, name)
      definition.implementation.call(*arguments)
    rescue Signature::TypeMismatch, Signature::ArityMismatch
      raise unless disable_visit_errors

      nil
    end
  end
end

require_relative "functions/signature"
