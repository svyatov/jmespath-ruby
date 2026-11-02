# frozen_string_literal: true

module JMESPath
  # Immutable syntax failure data returned by {JMESPath.validate}.
  class SyntaxDiagnostic
    # @return [String] reason without coordinates
    attr_reader :reason
    # @return [String] expression stored by the parser
    attr_reader :expression
    # @return [Integer, nil] zero-based byte offset, or nil for unknown locations
    attr_reader :position
    # @return [Integer, nil] one-based line, or nil for unknown locations
    attr_reader :line
    # @return [Integer, nil] one-based Unicode character column, or nil for unknown locations
    attr_reader :column

    # @api private
    def initialize(error)
      @reason = error.reason.dup.freeze
      @expression = error.expression.dup.freeze
      @position = error.position if error.location_known?
      @line = error.line if error.location_known?
      @column = error.column if error.location_known?
      freeze
    end

    # @return [Boolean] whether parsing reported a source location
    def location_known?
      !position.nil?
    end
  end
end
