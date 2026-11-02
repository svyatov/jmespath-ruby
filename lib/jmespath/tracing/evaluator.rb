# frozen_string_literal: true

module JMESPath
  module Tracing
    # @api private
    class Evaluator < JMESPath::Evaluator
      def initialize(functions:, collector:, disable_visit_errors: false)
        @collector = collector
        super(functions: functions, disable_visit_errors: disable_visit_errors)
      end

      def evaluate(node, data)
        return super unless node.kind == :field

        result, reason = FieldLookup.call(data, node.value.to_s)
        @collector.emit("field_null", node, name: node.value.to_s, reason: reason) if reason
        result
      end
    end
  end
end
