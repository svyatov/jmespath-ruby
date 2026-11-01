# frozen_string_literal: true

module JMESPath
  # @api private
  class Evaluator
    HANDLERS = {
      literal: :literal, index: :index,
      group: :group, subexpression: :sequence, pipe: :sequence,
      and: :boolean, or: :boolean, not: :negation?,
      eq: :equality, ne: :equality, lt: :ordering, lte: :ordering, gt: :ordering, gte: :ordering,
      multi_select_list: :list, multi_select_hash: :mapping,
      function: :function, expression_reference: :reference,
      projection: :projection, value_projection: :value_projection,
      filter_projection: :filter_projection, flatten: :flatten, slice: :slice
    }.freeze

    def initialize(functions:, disable_visit_errors: false)
      @functions = functions
      @disable_visit_errors = disable_visit_errors
      freeze
    end

    def evaluate(node, data)
      case node.kind
      when :field then DataAccess.field(data, node.value.to_s)
      when :current then data
      else send(HANDLERS.fetch(node.kind), node, data)
      end
    end
  end
end

require_relative "evaluation/scalars"
require_relative "evaluation/logic"
require_relative "evaluation/construction"
require_relative "evaluation/projections"
require_relative "evaluation/slices"
