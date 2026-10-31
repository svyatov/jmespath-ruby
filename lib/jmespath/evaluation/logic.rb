# frozen_string_literal: true

module JMESPath
  # @api private
  class Evaluator
    COMPARISONS = { lt: :<, lte: :<=, gt: :>, gte: :>= }.freeze

    private

    def boolean(node, data)
      # @type var result: value
      result = nil
      node.children.each do |child|
        result = evaluate(child, data)
        break if node.kind == :or ? !Types.falsey?(result) : Types.falsey?(result)
      end
      result
    end

    def negation?(node, data)
      Types.falsey?(evaluate(node.children.fetch(0), data))
    end

    def equality(node, data)
      left, right = node.children.map { |child| evaluate(child, data) }
      result = Types.equal?(left, right)
      node.kind == :eq ? result : !result
    end

    def ordering(node, data)
      left, right = node.children.map { |child| evaluate(child, data) }
      type = Types.name(left)
      return nil unless type == Types.name(right) && %i[number string].include?(type)

      if type == :string
        left = Functions::Coercions.string(left)
        right = Functions::Coercions.string(right)
      end
      left.public_send(COMPARISONS.fetch(node.kind), right)
    end
  end
end
