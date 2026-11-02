# frozen_string_literal: true

module JMESPath
  # @api private
  class Explanation
    OPERATORS = { eq: "==", ne: "!=", lt: "<", lte: "<=", gt: ">", gte: ">=" }.freeze
    ROLES = {
      group: "expression", subexpression: "step", pipe: "step", index: "input", slice: "input",
      flatten: "input", projection: %w[input expression].freeze, value_projection: %w[input expression].freeze,
      filter_projection: %w[input condition expression].freeze, expression_reference: "expression",
      function: "argument", and: "operand", or: "operand", not: "operand",
      comparison: %w[left right].freeze, multi_select_list: "element", multi_select_hash: "entry", entry: "expression"
    }.freeze

    def self.build(source, root)
      # @type var result: explanation
      result = { source: source.encode(Encoding::UTF_8).freeze, root: new.node(root) }
      result.freeze
    end

    def initialize
      @next_id = 0
    end

    def node(syntax)
      id = @next_id
      @next_id += 1
      operation = operation(syntax.kind)
      # @type var range: [Integer, Integer]?
      range = syntax.synthetic? ? nil : [syntax.start, syntax.finish].freeze
      # @type var result: explanation_node
      result = {
        id: id, operation: operation,
        source_range: range,
        details: details(syntax).freeze, children: children(syntax, operation).freeze
      }
      result.freeze
    end

    private

    def operation(kind)
      return "comparison" if OPERATORS.key?(kind)
      return "entry" if kind == :pair

      kind.to_s.freeze
    end

    def details(syntax)
      operator = OPERATORS[syntax.kind]
      return { operator: operator } if operator

      case syntax.kind
      when :field, :function, :pair then { name: syntax.value.to_s.dup.freeze }
      when :literal then { value: snapshot(syntax.value) }
      when :index then { index: Integer(syntax.value) }
      when :slice then slice_details(syntax.value)
      else {}
      end
    end

    def slice_details(value)
      start, stop, step = Array(value)
      { start: snapshot(start), stop: snapshot(stop), step: snapshot(step) }
    end

    def children(syntax, operation)
      roles = ROLES.fetch(operation.to_sym, [])
      syntax_children(syntax).each_with_index.map do |entry, index|
        # @type var result: explanation_child
        result = { role: roles.is_a?(String) ? roles : roles.fetch(index), node: node(entry) }
        result.freeze
      end
    end

    def syntax_children(syntax)
      return syntax.children unless syntax.kind == :filter_projection

      [syntax.children.fetch(0), syntax.children.fetch(2), syntax.children.fetch(1)]
    end

    def snapshot(value)
      case value
      when Hash then value.to_h { |key, entry| [key.to_s.dup.freeze, snapshot(entry)] }.freeze
      when Array then value.map { |entry| snapshot(entry) }.freeze
      when String then value.dup.freeze
      else value
      end
    end
  end
end
