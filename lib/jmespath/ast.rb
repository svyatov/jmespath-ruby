# frozen_string_literal: true

module JMESPath
  # @api private
  module AST
    # Immutable syntax and literal templates.
    class Node
      attr_reader :kind, :value, :children, :start, :finish, :depth

      def initialize(kind:, value: nil, children: [], start: 0, finish: 0)
        @kind = kind
        @value = self.class.immutable(value)
        @children = children.freeze
        @start = start
        @finish = finish
        @depth = (children.map(&:depth).max || -1) + 1
        freeze
      end

      def self.immutable(value)
        case value
        when Array then value.map { |item| immutable(item) }.freeze
        when Hash then value.transform_values { |item| immutable(item) }.freeze
        when String then value.dup.freeze
        else value
        end
      end
    end
  end
end
