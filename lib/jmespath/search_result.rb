# frozen_string_literal: true

module JMESPath
  # Immutable outcome of an expression search, retaining the original value or error.
  class SearchResult
    # @return [Object] the successful value, or nil on failure
    attr_reader :value
    # @return [StandardError, nil] the original library-owned failure
    attr_reader :error

    # @api private
    def initialize(value:, error:)
      @value = value
      @error = error
      freeze
    end

    # @return [Boolean] whether evaluation succeeded, including a null result
    def success?
      error.nil?
    end
  end
end
