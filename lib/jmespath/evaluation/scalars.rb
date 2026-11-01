# frozen_string_literal: true

module JMESPath
  # @api private
  class Evaluator
    private

    def literal(node, _data)
      copy_literal(node.value)
    end

    def copy_literal(value)
      case value
      when Array then value.map { |item| copy_literal(item) }
      when Hash then value.transform_values { |item| copy_literal(item) }
      when String then value.dup
      else value
      end
    end

    def index(node, data)
      array = DataAccess.array(evaluate(node.children.fetch(0), data))
      position = node.value
      raise TypeError, "Invalid array index" unless position.is_a?(Integer)

      return nil unless array && position.between?(-array.length, array.length - 1)

      array[position]
    end

    def group(node, data)
      evaluate(node.children.fetch(0), data)
    end

    def sequence(node, data)
      node.children.each { |child| data = evaluate(child, data) }
      data
    end

    def reference(node, _data)
      ExpressionReference.new { |value| evaluate(node.children.fetch(0), value) }
    end

    def function(node, data)
      arguments = node.children.map { |child| evaluate(child, data) }
      @functions.call(node.value.to_s, arguments, disable_visit_errors: @disable_visit_errors)
    end
  end
end
