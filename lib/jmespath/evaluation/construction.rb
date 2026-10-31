# frozen_string_literal: true

module JMESPath
  # @api private
  class Evaluator
    private

    def list(node, data)
      return nil if data.nil?

      node.children.map { |child| evaluate(child, data) }
    end

    def mapping(node, data)
      return nil if data.nil?

      node.children.to_h { |pair| [pair.value.to_s, evaluate(pair.children.fetch(0), data)] }
    end
  end
end
