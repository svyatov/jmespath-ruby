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

      private

      def project(node, values)
        return nil unless values

        index = -1
        child = node.children.fetch(1)
        result = values.map do |value|
          index += 1
          project_item(node, child, value, index)
        end
        result.compact!
        result
      end

      def project_item(node, child, value, index)
        @collector.within(node, index) do
          result = evaluate(child, value)
          @collector.emit("projection_omission", node) if result.nil?
          result
        end
      end

      def filter_projection(node, data)
        values = DataAccess.array(evaluate(node.children.fetch(0), data))
        indexes = [] # : Array[Integer]
        index = -1
        selected = values&.reject do |value|
          index += 1
          rejected = filter_rejected?(node, value, index)
          indexes << index unless rejected
          rejected
        end
        return nil unless selected

        project_selected(node, selected, indexes)
      end

      def filter_rejected?(node, value, index)
        @collector.within(node, index) do
          rejected = Types.falsey?(evaluate(node.children.fetch(2), value))
          @collector.emit("filter_exclusion", node) if rejected
          rejected
        end
      end

      def project_selected(node, selected, indexes)
        position = -1
        child = node.children.fetch(1)
        selected.map! do |value|
          position += 1
          project_item(node, child, value, indexes.fetch(position))
        end
        selected.compact!
        selected
      end
    end
  end
end
