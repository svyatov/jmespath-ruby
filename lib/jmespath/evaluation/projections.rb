# frozen_string_literal: true

module JMESPath
  # @api private
  class Evaluator
    private

    def projection(node, data)
      values = DataAccess.array(evaluate(node.children.fetch(0), data))
      project(node, values)
    end

    def value_projection(node, data)
      mapping = DataAccess.object(evaluate(node.children.fetch(0), data))
      project(node, mapping&.values)
    end

    def filter_projection(node, data)
      values = DataAccess.array(evaluate(node.children.fetch(0), data))
      selected = values&.reject { |value| Types.falsey?(evaluate(node.children.fetch(2), value)) }
      project(node, selected)
    end

    def project(node, values)
      values&.map { |value| evaluate(node.children.fetch(1), value) }&.compact
    end

    def flatten(node, data)
      values = DataAccess.array(evaluate(node.children.fetch(0), data))
      values&.flat_map { |value| DataAccess.array(value) || [value] }
    end
  end
end
