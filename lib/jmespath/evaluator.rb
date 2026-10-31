# frozen_string_literal: true

module JMESPath
  # @api private
  class Evaluator
    HANDLERS = {
      field: :field, current: :current, literal: :literal, index: :index,
      group: :group, subexpression: :sequence, pipe: :sequence,
      and: :boolean, or: :boolean, not: :negation?,
      eq: :equality, ne: :equality, lt: :ordering, lte: :ordering, gt: :ordering, gte: :ordering,
      multi_select_list: :list, multi_select_hash: :mapping,
      function: :function, expression_reference: :reference
    }.freeze

    def initialize(functions:, disable_visit_errors: false)
      @functions = functions
      @disable_visit_errors = disable_visit_errors
      freeze
    end

    def evaluate(node, data)
      handler = HANDLERS.fetch(node.kind)
      send(handler, node, data)
    end
  end
end

require_relative "evaluation/scalars"
require_relative "evaluation/logic"
require_relative "evaluation/construction"
