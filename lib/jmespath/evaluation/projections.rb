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
      return nil unless selected

      child = node.children.fetch(1)
      selected.map! { |value| evaluate(child, value) }
      selected.compact!
      selected
    end

    def project(node, values)
      return nil unless values

      child = node.children.fetch(1)
      result = values.map { |value| evaluate(child, value) }
      result.compact!
      result
    end

    def flatten(node, data)
      values = DataAccess.array(evaluate(node.children.fetch(0), data))
      values&.flat_map { |value| DataAccess.array(value) || [value] }
    end
  end
end
